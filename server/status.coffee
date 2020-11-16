
import cpustat from 'cpu-stat'
import diskspace from 'diskspace'
import os from 'os'
import rsync from 'rsync'
import Future from 'fibers/future'
import fs from 'fs'
import moment from 'moment'



status_present = new API.collection 'status_present'



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

API.add 'status/present', get: () -> return API.status.present this.queryParams.who

API.add 'status/load', get: () -> return API.status.load this.queryParams.values, this.queryParams.group, this.queryParams.q, this.queryParams.functions, this.queryParams.notify



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
          #.set('delete-after')
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



API.status.present = (who) ->
  if typeof who is 'string' and not already = status_present.find 'who.exact:"' + who + '" AND createdAt:>' + (Date.now() - 60000)
    status_present.insert who: who
  return history: (r._source for r in status_present.search('*', {newest: true, size:100}).hits.hits), who: status_present.terms 'who'
# TODO add a loop to check from main machine if nobody has been present for five mins, send an alert


API.status._lastwarn = {}
API.status._lastload = false
API.status._lastloadrun = Date.now()
API.status.load = (values=true, group=false, q='*', functions=false, notify=false) ->
  API.status._lastloadrun = Date.now()
  q += '*' if q.indexOf('*') is -1
  group = group.split(',') if typeof group is 'string'
  day = Math.floor((Date.now()-moment().startOf('day').valueOf())/864000)/100
  groups = {}
  times = ['today','yesterday']
  week = moment().subtract(7,'d').format('YYYYMMDD')
  month = moment().subtract(1,'months').format('YYYYMMDD')
  times.push week
  times.push month
  if API.status._lastload isnt false and API.status._lastload[week]?
    groups = API.status._lastload
    times = ['today']
  tq = if group isnt false then 'group.exact:"'+group.join('" OR group.exact:"') + '"' else q
  tq = '(' + tq + ') AND ' + q if group isnt false and q isnt '*'
  if functions is false and group isnt false
    functions = true if API.log.query({q: '(' + tq + ') AND path.exact:*', size: 0}).hits.total is 0
  for t in times
    for f in API.log.query({q: tq, size: 0, terms: [if group isnt false then 'path.exact' else if functions isnt false then 'function.exact' else 'group.exact']}, t, true).facets[if group isnt false then 'path.exact' else if functions isnt false then 'function.exact' else 'group.exact'].terms
      if group isnt false
        for fg in group
          if f.term.indexOf((if functions is false then '' else '.') + fg) isnt -1
            ft = f.term.split((if functions is false then '' else '.') + fg)[1]
            break
      else
        ft = f.term.split('.')[0]
      ft = ft.split(',')[0].replace(/"/g,'').replace('[','') if ft.indexOf('[') is 0 # skip some bad group names created in logs in error on dev
      groups[ft] ?= group: ft, value: 0
      if t is 'today'
        groups[ft].value = API.log.query({q: 'group.exact:"' + ft + '" AND createdAt:>' + (Date.now()-300000) + (if q isnt '*' then ' AND ' + q else ''), size: 0}).hits.total
        if values
          bs = API.log.query({q: (if group isnt false then 'group.exact:"' + ft + '"' else if functions then 'function.exact:"'+f+'"' else 'path.exact:"'+f+'"') + (if q isnt '*' then ' AND ' + q else ''), size: 0, aggs: {history: {date_histogram: {field: 'createdAt', interval: '5m'}}}}, 'today', true).aggregations.history.buckets
          for b of bs
            groups[ft].values ?= []
            if b isnt '0'
              cd = 0
              while cd < (bs[b].key - bs[parseInt(b)-1].key)/300000
                groups[ft].values.push 0
                cd += 1
            groups[ft].values.push bs[b].doc_count
      groups[ft][t] = f.count
  for s in API.log.stack(if q isnt '*' then q else undefined)
    for gs in (if group isnt false then (if s.path then [s.path] else if functions and s.function then [s.function] else []) else (if functions and s.function then [s.function] else if typeof s.group is 'string' then [s.group] else s.group ? []))
      hg = if group is false then true else false
      if hg is false
        for egs in group
          if gs.indexOf(egs) isnt -1
            hg = egs
            break
      if parseInt(s.createdAt) > Date.now()-300000 and hg
        gs = gs.split(hg)[1] if group isnt false
        groups[gs] ?= group: gs, value: 1
        groups[gs].today ?= 0
        groups[gs].today += 1
        groups[gs].value ?= 0
        groups[gs].value += 1
        groups[gs].stack ?= 0
        groups[gs].stack += 1
  warn = []
  for g of groups
    groups[g].today ?= 0
    groups[g].yesterday ?= 0
    groups[g].weekago = groups[g][week] ? 0
    groups[g].monthago = groups[g][month] ? 0
    groups[g].avg = Math.floor (groups[g].yesterday + groups[g].weekago + groups[g].monthago)/3
    groups[g].day = day
    groups[g].interpolate = Math.ceil groups[g].avg * day #* (groups[g].avg/groups[g].today)
    groups[g].percent = if groups[g].interpolate is 0 then 0 else Math.ceil (groups[g].today / groups[g].interpolate)*100
    if values
      groups[g].values ?= []
      while groups[g].values.length < (86400000/300000)*day
        groups[g].values.unshift 0
      if groups[g].day > 0.15 and groups[g].today isnt groups[g].avg and (groups[g].percent > 250 or groups[g].percent < 30)
        # compare to this time yesterday
        groups[g].yn = API.log.query({q: (if group isnt false then 'path:"' + g else if functions then 'function.exact:"' + g else 'group.exact:"' + g) + '" AND createdAt:<' + moment().subtract(1,'day').valueOf() + (if q isnt '*' then ' AND ' + q else ''), size: 0}, 'yesterday', true).hits.total
        if groups[g].yn > groups[g].today # if more by the same time yesterday than at current time today, continue to check if a warning is necessary 
          groups[g].days = []
          for d in API.log.query({q: (if group isnt false then 'path:"' + g else if functions then 'function.exact:"' + g else 'group.exact:"' + g) + '" AND createdAt:>' + moment().subtract(1,'months').valueOf() + (if q isnt '*' then ' AND ' + q else ''), size: 0, aggs: {history: {date_histogram: {field: 'createdAt', interval: 'day'}}}}, '', true).aggregations.history.buckets
            groups[g].days.push d.doc_count
          groups[g].dvg = Math.floor groups[g].days.reduce(((a, b) => a + b), 0) / groups[g].days.length
          groups[g].warn = true if groups[g].interpolate >= groups[g].dvg or groups[g].interpolate < Math.min.apply Math, groups[g].days
          warn.push(g) if groups[g].warn
  API.status._lastload = groups
  if warn.length and notify
    console.log API.status._lastwarn
    txt = ''
    warns = []
    for w in warn
      # don't send another warning if within 12 hours of the last one, because once something gets a 
      # warning during a given day, it likely keeps getting a warning, which is not useful
      if not API.status._lastwarn[w]? or API.status._lastwarn[w] < Date.now()-43200000
        API.status._lastwarn[w] = Date.now()
        warns.push w
        txt += w + ', current ' + groups[w].value + ', today ' + groups[w].today + ', yesterday ' + groups[w].yesterday + ', average ' + groups[w].avg + ', ' + groups[w].percent + '%\n'
    if warns.length
      API.mail.send
        from: 'alert@cottagelabs.com'
        to: 'alert@cottagelabs.com'
        subject: (if API.settings.dev then 'Dev' else 'Live') + ' load levels outside normal ranges for ' + warns.join(',')
        text: txt + '\n\n' #+ JSON.stringify groups, '', 2
  return groups

# run load check on the main machine every 15 mins if not recently done
_loadcheck = () ->
  if API.settings.cluster?.ip? and API.status.ip() not in API.settings.cluster.ip
    API.log 'Setting up a load check to run at least every 15 mins if not triggered by request on ' + API.status.ip()
    Meteor.setInterval (() ->
      if API.status._lastloadrun < Date.now()-900000
        API.log 'Running status load check at max 15 minute interval'
        API.status.load undefined, undefined, undefined, undefined, true
      ), 900000
#Meteor.setTimeout _loadcheck, 21000
