

API.add 'memory', get: () -> return {cid:process.env.CID, appid:process.env.APP_ID, memory:process.memoryUsage()}

API.add 'status', get: () -> return API.status(false)

API.status = (email=true) ->
  ret =
    status: 'green' # can also be yellow if there are non-critical problems, or red if problems
    up:
      live: false
      local: false
      cluster: false
      dev: false
    memory: [{machine:'served', cid:process.env.CID, appid:process.env.APP_ID, memory:process.memoryUsage()}]
    accounts:
      total: Users.count()
    job: false
    service: {}
    use: {}
    index: false

  # on first startup, need to create at least one account (which becomes root) to be safe
  ret.status = 'red' if ret.accounts.total is 0

  try ret.up.live = true if HTTP.call 'HEAD', 'https://api.cottagelabs.com', {timeout:2000}
  try ret.up.local = true if lm = HTTP.call 'GET', 'https://local.api.cottagelabs.com/memory', {timeout:2000}
  try ret.up.dev = true if dm = HTTP.call 'GET', 'https://dev.api.cottagelabs.com/memory', {timeout:2000}
  if lm?.data?
    lm.data.machine = 'local'
    ret.memory.push lm.data
  if dm?.data?
    dm.data.machine = 'dev'
    ret.memory.push dm.data
  try
    HTTP.call 'HEAD','https://cluster.api.cottagelabs.com', {timeout:2000}
    ret.up.cluster = true
    if API.settings.cluster?.machines
      cm = 0
      for m in API.settings.cluster.machines
        try
          cm = HTTP.call 'GET','http://' + m + '/api/memory', {timeout:2000}
          cm.data.machine = m
          ret.memory.push cm.data
          cm += 1
      ret.up.cluster = cm if cm isnt 0
      ret.status = 'yellow' if cm isnt API.settings.cluster.machines.length
  ret.status = 'red' if ret.up.cluster is false or ret.up.cluster is 0

  try ret.job = API.job.status()
  try ret.index = API.es.status()
  ret.status = 'yellow' if ret.status isnt 'red' and (ret.job is false or ret.index is false)
  ret.status = ret.index.cluster.status if ret.index isnt false and ret.status isnt 'red' and ret.index.cluster?.status in ['red','yellow']

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

