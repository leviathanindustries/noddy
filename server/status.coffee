
import cpustat from 'cpu-stat'
import diskspace from 'diskspace'

API.add 'stats',
  get: () ->
    ret = {
      cid: process.env.CID, 
      appid: process.env.APP_ID, 
      updated: process.env.LAST_UPDATED,
      memory: process.memoryUsage(), 
      cpu: Meteor.wrapAsync((callback) -> cpustat.usagePercent((err, percent, seconds) -> console.log(err); return callback(null, percent)))(), 
      disk: Meteor.wrapAsync((callback) -> diskspace.check('/', (err, result) -> console.log(err); return callback(null, result)))(), 
      name: (if API.settings.name then API.settings.name else 'API'),
      version: (if API.settings.version then API.settings.version else "0.0.1"),
      dev: API.settings.dev
    }
    try
      ret.disk.human = Math.round(ret.disk.used/ret.disk.total*100) + '% used of ' + Math.round(ret.disk.total/1024/1024/1024) + 'G'
      ret.memory.human = Math.round(ret.memory.heapUsed/ret.memory.heapTotal*100) + '% used of ' + Math.round(ret.memory.rss/1024/1024) + 'M allocated (max default that node will allow this to go up to is 1.7G)'
    return ret

API.add 'status', get: () -> return API.status(false)

API.status = (email=true) ->
  ret =
    status: 'green' # can also be yellow if there are non-critical problems, or red if problems
    up:
      live: false
      local: false
      cluster: false
      dev: false
    machines: []
    accounts:
      total: Users.count()
    job: false
    service: {}
    use: {}
    index: false

  # on first startup, need to create at least one account (which becomes root) to be safe
  ret.status = 'red' if ret.accounts.total is 0

  try ret.up.live = true if HTTP.call 'HEAD', 'https://api.cottagelabs.com', {timeout:2000}
  try ret.up.local = true if lm = HTTP.call 'GET', 'https://local.api.cottagelabs.com/stats', {timeout:2000}
  try ret.up.dev = true if dm = HTTP.call 'GET', 'https://dev.api.cottagelabs.com/stats', {timeout:2000}
  reported = false
  if lm?.data?
    lm.data.machine = 'local'
    if lm.data.cid is process.env.CID
      reported = true
      lm.data.served = true
    ret.machines.push lm.data
  if dm?.data?
    dm.data.machine = 'dev'
    if dm.data.cid is process.env.CID
      reported = true
      dm.data.served = true
    ret.machines.push dm.data
  try
    HTTP.call 'HEAD','https://cluster.api.cottagelabs.com', {timeout:2000}
    ret.up.cluster = true
    if API.settings.cluster?.ip
      API.settings.cluster.ip = [API.settings.cluster.ip] if typeof API.settings.cluster.ip is 'string'
      ccount = 0
      for m in API.settings.cluster.ip
        try
          cm = HTTP.call 'GET',(if m.indexOf('http') isnt 0 then 'http://' else '') + m + (if m.indexOf(':') is -1 then ':3000' else '') + '/api/stats', {timeout:2000}
          cm.data.machine = m
          if cm.data.cid is process.env.CID
            reported = true
            cm.data.served = true
          ret.machines.push cm.data
          ccount += 1
      ret.up.cluster = ccount if ccount isnt 0
      ret.status = 'yellow' if ccount isnt API.settings.cluster.ip.length
  if not reported
    ret.machines.push {served:true, cid:process.env.CID, appid:process.env.APP_ID, memory:process.memoryUsage()}
  ret.status = 'red' if API.settings.cluster?.machines and API.settings.cluster.ip.length and (ret.up.cluster is false or ret.up.cluster is 0)

  try ret.job = API.job.status()
  try ret.index = API.es.status()
  ret.status = 'yellow' if ret.status isnt 'red' and (ret.job is false or ret.index is false)
  ret.status = ret.index.cluster.status if ret.index isnt false and ret.status isnt 'red' and ret.index.cluster?.status not in (API.settings.es?.status ? ['green'])

  for s of API.service
    if typeof API.service[s].status is 'function'
      try ret.service[s] = API.service[s].status()
      # TODO how to set the overall status if this does not return as expected?

  for u of API.use
    if typeof API.use[u].status is 'function'
      try
        ret.use[u] = API.use[u].status()
      catch
        ret.use[u] = false
      ret.status = 'yellow' if ret.status isnt 'red' and ret.use[u] isnt true

  # TODO if ret.status isnt green, should a notification email get sent?
  return ret

