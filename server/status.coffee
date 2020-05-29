
import cpustat from 'cpu-stat'
import diskspace from 'diskspace'
import os from 'os'
import rsync from 'rsync'
import Future from 'fibers/future'
import fs from 'fs'

API.add 'status', get: () -> return API.status this.queryParams.email, this.queryParams.accounts, this.queryParams.service, this.queryParams.use, this.queryParams.job, this.queryParams.index, this.queryParams.detailed

API.add 'status/stats',
  get: () ->
    ret = {
      ip: API.status.ip(),
      appid: process.env.APP_ID, 
      updated: process.env.LAST_UPDATED,
      memory: process.memoryUsage(), 
      cpu: Async.wrap((callback) -> cpustat.usagePercent((err, percent, seconds) -> console.log(err); return callback(null, percent)))(), 
      disk: Async.wrap((callback) -> diskspace.check('/', (err, result) -> console.log(err); return callback(null, result)))(), 
      name: (if API.settings.name then API.settings.name else 'API'),
      version: (if API.settings.version then API.settings.version else "0.0.1"),
      dev: API.settings.dev
    }
    try
      ret.disk.human = Math.round(ret.disk.used/ret.disk.total*100) + '% used of ' + Math.round(ret.disk.total/1024/1024/1024) + 'G'
      ret.memory.human = Math.round(ret.memory.heapUsed/ret.memory.heapTotal*100) + '% used of ' + Math.round(ret.memory.rss/1024/1024) + 'M allocated (max default that node will allow this to go up to is 1.7G)'
    return ret

API.add 'status/ip', get: () -> return API.status.ip()
API.add 'status/sync', 
  get: 
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.status.sync()
API.add 'status/bounce',
  get:
    roleRequired: if API.settings.dev then undefined else 'admin.bounce'
    action: () -> return API.status.bounce()
    


API.status = (email=false, accounts=false, service=false, use=false, job=false, index=true, detailed=false) ->
  if detailed
    accounts = true
    service = true
    use = true
    job = true

  ret =
    status: 'green' # can also be yellow if there are non-critical problems, or red if problems
    up:
      live: false
      local: false
      cluster: false
      dev: false
    machines: []

  if accounts
    ret.accounts = total: Users.count()
    # on first startup, need to create at least one account (which becomes root) to be safe
    ret.status = 'red' if ret.accounts.total is 0

  try ret.up.live = true if HTTP.call 'HEAD', 'https://api.cottagelabs.com', {timeout:2000}
  try ret.up.local = true if lm = HTTP.call 'GET', 'https://local.api.cottagelabs.com/status/stats', {timeout:2000}
  try ret.up.dev = true if dm = HTTP.call 'GET', 'https://dev.api.cottagelabs.com/status/stats', {timeout:2000}
  reported = false
  if lm?.data?
    lm.data.machine = 'local'
    if lm.data.ip is API.status.ip()
      reported = true
      lm.data.served = true
    ret.machines.push lm.data
  if dm?.data?
    dm.data.machine = 'dev'
    if dm.data.ip is API.status.ip()
      reported = true
      dm.data.served = true
    ret.machines.push dm.data
  try
    HTTP.call 'HEAD','https://cluster.api.cottagelabs.com', {timeout:2000}
    ret.up.cluster = true
  try
    if API.settings.cluster?.ip
      API.settings.cluster.ip = [API.settings.cluster.ip] if typeof API.settings.cluster.ip is 'string'
      ccount = 0
      for m in API.settings.cluster.ip
        try
          cm = HTTP.call 'GET',(if m.indexOf('http') isnt 0 then 'http://' else '') + m + (if m.indexOf(':') is -1 then (if API.settings.dev then ':3002' else ':3333') else '') + '/api/status/stats', {timeout:2000}
          cm.data.machine = m
          if cm.data.ip is API.status.ip()
            reported = cm.data.ip
            cm.data.served = true
          ret.machines.push cm.data
          ccount += 1
      ret.up.cluster = ccount if ccount isnt 0
      ret.status = 'yellow' if ccount isnt API.settings.cluster.ip.length
  if not reported
    ret.machines.push {served:true, ip:API.status.ip(), appid:process.env.APP_ID, memory:process.memoryUsage()}
  ret.status = 'red' if API.settings.cluster?.ip and API.settings.cluster.ip.length and (ret.up.cluster is false or ret.up.cluster is 0)
  ret.status = 'yellow' if typeof reported is 'string' and reported in API.settings.cluster.ip

  if job
    ret.job = false
    try ret.job = API.job.status()
    ret.status = 'yellow' if ret.status isnt 'red' and ret.job is false

  if service
    for s of API.service
      if typeof API.service[s].status is 'function'
        ret.service ?= {}
        try ret.service[s] = API.service[s].status()
        # TODO how to set the overall status if this does not return as expected?

  if use
    for u of API.use
      if typeof API.use[u].status is 'function'
        try
          ret.use ?= {}
          ret.use[u] = API.use[u].status()
        catch
          ret.use[u] = false
        ret.status = 'yellow' if ret.status isnt 'red' and ret.use[u] isnt true

  if index
    ret.index = false
    try ret.index = API.es.status()
    ret.status = 'yellow' if ret.status isnt 'red' and ret.index is false
    ret.status = ret.index.cluster.status if ret.index isnt false and ret.status isnt 'red' and ret.index.cluster?.status not in (API.settings.es?.status ? ['green'])

  # TODO if ret.status isnt green, should a notification email get sent?
  if ret.status isnt 'green'
    API.log {msg: 'Status check is not green', status: ret, function: 'API.status'}
  else if not detailed
    delete ret.machines
    if ret.index?.cluster?
      ret.index = {cluster: {cluster_name: ret.index.cluster.cluster_name, status: ret.index.cluster.status}} 
      ret.index.acceptable = API.settings.es.status if API.settings.es?.status?
  return ret

_sync_running = false
API.status.sync = (ips,src,dest) ->
  # this requires that the machine running it has the necessary keys and username, and that it has connected before manually to accept the key
  # also the src and dest folders must exists, and ideally a manual scp of the content should have been done first
  if API.settings.cluster?.ip? and API.status.ip() not in API.settings.cluster.ip
    ips ?= API.settings?.cluster?.ip
    ips = [ips] if typeof ips is 'string'
    src ?= if API.settings?.cluster?.sync?.src? then API.settings.cluster.sync.src else '/home/cloo/' + (if API.settings.dev then 'dev' else 'live') + '/noddy/'
    dest ?= if API.settings?.cluster?.sync?.dest? then API.settings.cluster.sync.dest else src
    done = []
    _sync = (ip) ->
      API.log 'begin sync ' + src + ' to ' + dest + ' on ' + ip
      if ip.indexOf(API.status.ip()) is -1
        ip = ip.split('//')[1] if ip.indexOf('//') isnt -1
        ip = ip.split('/')[0] if ip.indexOf('/') isnt -1
        rs = new rsync()
          .shell('ssh')
          .flags('azL')
          .set('exclude','.meteor/local')
          .source(src)
          .destination(ip + ':' + dest)
        rs.execute((error, code, cmd) -> 
          API.log 'end sync to ' + ip
          done.push(ip)
        )
    if _sync_running
      return false
    else if ips? and ips.length
      _sync_running = true
      _sync(i) for i in ips
      while done.length isnt ips.length
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 500
        future.wait()
      checkup = {}
      while _.keys(checkup).length isnt ips.length
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 12000
        future.wait()
        for ip in ips
          if ip.indexOf(API.status.ip()) is -1 and not checkup[ip]?
            ip = ip.split('//')[1] if ip.indexOf('//') isnt -1
            ip = ip.split('/')[0] if ip.indexOf('/') isnt -1
            addr = (if ip.indexOf('http') isnt 0 then 'http://' else '') + ip + (if ip.indexOf(':') is -1 then (if API.settings.dev then ':3002' else ':3333') else '') + '/api/status/stats'
            try
              console.log 'SYNC checking up on ' + addr
              cm = HTTP.call 'GET',addr, {timeout:5500}
              checkup[ip] = cm?.data?.version ? true
            catch
              console.log 'SYNC not yet up on ' + addr
      _sync_running = false
      console.log 'SYNC done'
    return version: (if API.settings.version then API.settings.version else "0.0.1"), done: done, checkup: checkup
  else
    return false

_status_ip = false
API.status.ip = () ->
  if _status_ip isnt false
    return _status_ip
  else
    for ifname of ifaces = os.networkInterfaces()
      iface = ifaces[ifname]
      for ift in iface
        if ift.family is 'IPv4' and ift.internal is false and ifname is 'eth1'
          _status_ip = ift.address
          return ift.address

# write a timestamp to a file in the code directory to cause a restart
API.status.bounce = () ->
  fn = if API.settings?.cluster?.bounce?.src? then API.settings.cluster.bounce.src else if API.settings?.cluster?.sync?.src? then API.settings.cluster.sync.src else '/home/cloo/' + (if API.settings.dev then 'dev' else 'live') + '/noddy/'
  fn += '/' if not fn.endsWith('/')
  fn += 'bounce.js'
  dn = Date.now()
  API.log 'Bounce'
  fs.writeFileSync fn, '_last_bounce=' + dn
  return dn

# whenever the system restarts check if auto sync is set
# or if the last bounce date in file is within the last 30 seconds, call sync
if API.settings.cluster?.ip? and API.status.ip() not in API.settings.cluster.ip
  fn = if API.settings?.cluster?.bounce?.src? then API.settings.cluster.bounce.src else if API.settings?.cluster?.sync?.src? then API.settings.cluster.sync.src else '/home/cloo/' + (if API.settings.dev then 'dev' else 'live') + '/noddy/'
  fn += '/' if not fn.endsWith('/')
  fn += 'bounce.js'
  try
    content = fs.readFileSync(fn).toString()
    last = parseInt content.split('=')[1]
  catch
    last = false

  if API.settings.cluster.sync? or last isnt false and last > Date.now() - 30000
    if last isnt false and last > Date.now() - 30000
      console.log 'TRIGGERING AUTOMATIC SYNC TO CLUSTER MACHINES DUE TO BOUNCE AT ' + last
      Meteor.setTimeout (() -> API.log msg: 'System successfully manually bounced at ' + Date.now(), notify: true), 10000
    else
      console.log 'TRIGGERING AUTOMATIC SYNC TO CLUSTER MACHINES DUE TO MAIN APP RELOAD ON FILE CHANGE WHILE RUNNING'
    API.status.sync()
