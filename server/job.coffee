
import { Random } from 'meteor/random'
import Future from 'fibers/future'
import crypto from 'crypto'
import moment from 'moment'

API.job = {}

# TODO could list _.keys process.env and for any starting with NODDY_SETTINGS_ use their remaining name to update the running settings
if API.settings.job? and API.settings.job.startup isnt true and (process.env.NODDY_SETTINGS_JOB_STARTUP is 'true' or process.env.NODDY_SETTINGS_JOB_STARTUP is 'True' or process.env.NODDY_SETTINGS_JOB_STARTUP is 'TRUE' or process.env.NODDY_SETTINGS_JOB_STARTUP is true)
  API.log 'Job runner altering job startup setting to true based on provided JOB_STARTUP env setting'
  API.settings.job.startup = true

@job_job = new API.collection index: API.settings.es.index + "_job", type: "job"
@job_process = new API.collection index: API.settings.es.index + "_job", type: "process"
@job_processing = new API.collection index: API.settings.es.index + "_job", type: "processing"
@job_result = new API.collection index: API.settings.es.index + "_job", type: "result"
@job_limit = new API.collection index: API.settings.es.index + "_job", type: "limit"
@job_cap = new API.collection index: API.settings.es.index + "_job", type: "cap"

API.add 'job',
  get: () -> return data: 'The job API'
  post:
    #roleRequired: 'job.user'
    action: () ->
      maxallowedlength = 3000 # TODO where should this really be set...
      checklength = this.request.body.processes?.length ? this.request.body.length
      if checklength > maxallowedlength
        return 413
      else
        j = {new:true, user:this.userId, processed:0}
        j._id = job_job.insert j # jobs created to provide immediate info to user
        j.processes = if this.request.body.processes then this.request.body.processes else this.request.body
        j.refresh ?= this.queryParams.refresh
        Meteor.setTimeout (() -> API.job.create j), 2
        return job:j._id

API.add 'job/:job',
  get:
    authRequired: true
    action: () ->
      if job = job_job.get this.urlParams.job
        if not API.job.allowed job, this.user
          return 401
        else
          job.progress = API.job.progress(job) if this.queryParams.progress
          if this.queryParams.processes?
            if typeof this.queryParams.processes is 'number'
              try job.processes = job.processes.slice(0,this.queryParams.processes)
            else if '-' in this.queryParams.processes
              try job.processes = job.processes.slice(parseInt(this.queryParams.processes.split('-')[0]),parseInt(this.queryParams.processes.split('-')[1]))
            else if this.queryParams.processes isnt true
              try
                pn = parseInt this.queryParams.processes
                job.processes = job.processes.slice(0,pn) if not isNaN pn
          else
            delete job.processes 
          return job
      else
        return 404
  delete:
    roleRequired: 'job.user' # who if anyone can remove jobs?
    action: () -> 
      return if not API.job.allowed(this.urlParams.job,this.user) then 401 else API.job.remove(job)

API.add 'job/:job/progress', get: () -> return if not job = job_job.get(this.urlParams.job) then 404 else API.job.progress job

API.add 'job/:job/results',
  get:
    # authRequired: true this has to be open if people are going to share jobs, but then what about jobs is closed?
    action: () ->
      job = job_job.get this.urlParams.job
      # return 401 if not API.job.allowed job,this.user
      return API.job.results this.urlParams.job, this.queryParams.full
API.add 'job/:job/results.csv',
  get:
    # authRequired: true this has to be open if people are going to share jobs, but then what about jobs is closed?
    action: () ->
      # return 401 if not API.job.allowed job,this.user
      return if not job = job_job.get(this.urlParams.job) then 404 else json2csv2response this, API.job.results(this.urlParams.job, this.queryParams.full), (if job.name then job.name.split('.')[0].replace(/ /g,'_') + '_results' else 'results')+".csv"

API.add 'job/:job/rerun',
  get:
    authOptional: true # TODO decide proper permissions for this and pass uid to job.rerun if suitable
    action: () -> return API.job.rerun(this.urlParams.job, this.userId)

API.add 'job/:job/reload',
  get:
    authOptional: true # TODO decide proper permissions for this
    action: () -> return API.job.reload(this.urlParams.job,this.queryParams.list)

API.add 'job/:job/complete',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.complete this.urlParams.job, this.queryParams.done?, this.queryParams.complete?, this.queryParams.list?, this.queryParams.known?

API.add 'job/reload',
  get:
    roleRequired: if API.settings.dev then undefined else 'job.admin'
    action: () -> return API.job.reload(true,this.queryParams.list) # reloads every process from every job that is not done, if there is not already a process or a result matching it

API.add 'job/complete',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.complete this.queryParams.q, this.queryParams.done?, this.queryParams.complete?, this.queryParams.list?, this.queryParams.known?

API.add 'job/orphans',
  get:
    roleRequired: if API.settings.dev then undefined else 'job.admin'
    action: () -> return API.job.orphans(this.queryParams.remove?,(if this.queryParams.types then this.queryParams.types.split(',') else undefined)) # removes any process or result that does not appear in a job currently in the system
  delete:
    roleRequired: if API.settings.dev then undefined else 'job.admin'
    action: () -> return API.job.orphans(true,(if this.queryParams.types then this.queryParams.types.split(',') else undefined)) # removes any process or result that does not appear in a job currently in the system

API.add 'job/jobs',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        processes = false
        if this.queryParams.processes
          delete this.queryParams.processes
          processes = true
        return job_job.search this.queryParams, (if processes or this.queryParams.fields or this.queryParams._source then undefined else {_source:{exclude:['processes']}})
      else
        return count: job_job.count(), done: job_job.count undefined, {done: true}

API.add 'job/jobs/:email',
  get:
    authRequired: not API.settings.dev
    action: () ->
      if this.user? and not API.accounts.auth('job.admin',this.user) and this.user.emails[0].address isnt this.urlParams.email
        return 401
      else
        results = []
        done = 0
        job_job.each {email:this.urlParams.email}, (if this.queryParams.processes then {size:this.queryParams.size ? 20} else {_source: {exclude:['processes']}}), ((job) -> done += if job.done then 1 else 0; results.push job)
        return total: results.length, jobs: results, done: done

API.add 'job/results',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_result.search this.queryParams
      else
        return count: job_result.count()

API.add 'job/result/:_id',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return job_result.get this.urlParams._id

API.add 'job/limits',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_limit.search this.queryParams
      else
        return count: job_limit.count()

API.add 'job/processes',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_process.search this.queryParams
      else
        return count: job_process.count()

API.add 'job/processing',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_processing.search this.queryParams
      else
        return count: job_processing.count()

API.add 'job/processing/reload',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.reload()

API.add 'job/clear/:which',
  get:
    authRequired: 'root'
    action: () ->
      pq = _.clone this.queryParams
      delete pq.apikey if pq.apikey?
      pq = '*' if _.isEmpty pq
      if this.urlParams.which is 'results'
        return job_result.remove pq
      else if this.urlParams.which is 'processes'
        res = job_process.remove pq
        return res
      else if this.urlParams.which is 'processing'
        return job_processing.remove pq
      else if this.urlParams.which is 'jobs'
        return API.job.remove pq
      else
        return false

API.add 'job/process/:proc',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.process this.urlParams.proc

API.add 'job/status', get: () -> return API.job.status()

API.add 'job/start',
  get:
    roleRequired: 'job.admin'
    action: () -> API.job.start(); return true
API.add 'job/stop',
  get:
    roleRequired: 'job.admin'
    action: () -> API.job.stop(); return true



API.job._sign = (fn='', args, checksum=true) ->
  fn += '_'
  if typeof args is 'string'
    fn += args
  else
    try
      for a in _.keys(args).sort()
        fn += a + '_' + JSON.stringify(args[a]) if a not in ['plugin']
    catch
      fn += JSON.stringify args
  sig = encodeURIComponent(fn) # just used to use this, but got some where args were too long
  return if checksum then crypto.createHash('md5').update(sig, 'utf8').digest('base64') else sig

API.job.allowed = (job,uacc) ->
  job = job_job.get(job) if typeof job is 'string'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'
  return if not job or not uacc then false else job.user is uacc._id or API.accounts.auth 'job.admin',uacc

API.job.create = (job) ->
  job = job_job.get(job) if typeof job isnt 'object'
  job.processes ?= []
  job.count = job.processes.length
  # A job can set the "service" value to indicate which service it belongs to, so that queries about jobs only related to the service can be performed
  # NOTE there is a process priority field which can be set from the job too - how to decide who can set priorities?
  job.priority ?= if job.count <= 10 then 11 - job.count else 0 # set high priority for short jobs more likely to be from a UI
  # A job can have order:true if so, processes will be set to available:false and only run once their previous process completes and changes this
  # TODO what is best default refresh for job? And should it change from current use as days down to ms?
  job.args = JSON.stringify(job.args) if job.args? and typeof job.args isnt 'string' # store args as string so can handle multiple types
  imports = []
  for i of job.processes
    # processes list can contain string name of function to run, or else assumed to be different args for the overall job function
    proc = if typeof job.processes[i] is 'string' and job.processes[i].indexOf('API.') is 0 then {function: job.processes[i]} else (if typeof job.processes[i] is 'object' and job.processes[i].function? then job.processes[i] else {function: job.function, args:job.processes[i]})
    proc.service ?= job.service # just for useful info, if provided by the service that creates the job
    proc.priority ?= job.priority # higher priority runs sooner, otherwise runs at random - who can set this?
    proc.function ?= job.function # string name of the function to run
    proc.args ?= job.args # args to pass to the function, if any
    proc.args = JSON.stringify(proc.args) if proc.args? and typeof proc.args isnt 'string' # args stored in index as string so can handle different types
    if job.order is true
      job.refresh = 0 # an ordered job has to use fresh results, so that it uses results created in order (else why bother ordering it?)
      proc.job = job._id # only needed if job has order, and otherwise should not be set as processes can be shared across jobs
      proc.order = parseInt(i)
      proc.available = not proc.order # only first process is available to start
    # The repeat option below is probably best set per process than per job. If true or number, the finished process creates another process
    # (and does not check for cached results, so new process and fresh results every time). Counts down until reaches zero, or if true, forever
    # For a process that repeats AND is in an ordered job, it will complete all repeats before kicking off the next process
    proc.repeat ?= job.repeat
    proc.limit ?= job.limit # option number of ms to wait before starting another one
    proc.group ?= job.group ? proc.function # group name string necessary for limit to compare against
    # NOTE, group defaults to process function name string, because it is usually more useful to limit certain functions
    # than the set of processes of a job. This also usefully limits in relation to processes in separate jobs running in the same cluster.
    # To group all processes of a job where they have different functions, provide a unique group name.
    # NOTE when a process calls its function, it gives itself as an object as the first argument. This would include the "original" field
    # which is the ID of the first process that ran in the repeat, and a "counter". Each process will have a unique ID and will have
    # written its result to job_result with that ID, so a repeat could run on a function that does something with the result of the
    # previous time it ran, by searching for the "original" key sorted by "counter", until the repeat comes to an end. Could be useful.
    # also for convenience the following processes will contain the result field until they overwrite it with their own result.
    # if the previous process succeeded, the result object will contain a key named the same as the function name, and that will
    # point to the actual results object, to help avoid mapping collisions. If functions could return things that still cause
    # collisions, they will actually be stringified and saved under the result.string key, so look there if looking them up.
    # However the returned (or callbacked) result object will still have the JSON version as normal.
    proc.callback ?= job.callback # optional callback name string per job or process, will call when process completes. Processes do return too, so either way is good
    proc.signature = API.job._sign proc.function, proc.args # combines with refresh to decide if need to run process or just pick up result from a same recent process
    proc.createdAt = Date.now()
    proc.created_date = moment(proc.createdAt, "x").format "YYYY-MM-DD HHmm.ss"

    job.refresh = 0 if job.refresh is true
    job.refresh = parseInt(job.refresh) if typeof job.refresh is 'string'
    if job.refresh is 0 or proc.callback? or proc.repeat?
      proc._id = Random.id()
      imports.push proc
    else
      match = {must:[{term:{'signature.exact':proc.signature}}], must_not:[{exists:{field:'_raw_result.error'}}]}
      try
        if typeof job.refresh is 'number' and job.refresh isnt 0
          d = new Date()
          match.must.push {range:{createdAt:{gt:d.setDate(d.getDate() - job.refresh)}}}
      rs = job_result.find match, true
      rs = job_processing.find({'signature.exact':proc.signature}, true) if not rs?
      rs = job_process.find({'signature.exact':proc.signature}, true) if not rs?
      if rs
        proc._id = rs._id
      else
        proc._id = Random.id()
        imports.push proc

    job.processes[i] = proc

  if imports.length
    job_process.insert imports
    job.processed = job.count - imports.length
    job.reused = job.processed # just store how many were already results at the start of the job, for potential useful info later
  else
    job.processed = 0
    job.done = true

  # NOTE job can also have a "complete" function string name, which will be called when progress hits 100%, see below
  # the "complete" function will receive the whole job object as the only argument (so can look up results by the process IDs)
  job.done ?= job.count is 0 # bit pointless submitting empty jobs, but theoretically possible. Could make impossible...
  job.new = false
  if job._id
    job_job.update job._id, job
  else
    job._id = job_job.insert job
  if job.done
    API.job.complete job
  return job

API.job.remove = (jorq) ->
  _remove = (job) ->
    try
      for p in job.processes
        if job_job.search('NOT _id:' + job._id + ' AND processes._id:' + p._id).hits.total is 0
          try job_process.remove p._id
          try job_processing.remove p._id
          try job_result.remove p._id
    job_job.remove job._id
  if (typeof jorq is 'object' and jorq._id?) or job_job.exists(jorq)
    job = if typeof jorq is 'object' then jorq else job_job.get jorq
    job = job_job.get(job._id) if not job.processes? # just in case this is passed a job without its process list, which can occur sometiems to save passing around large job objects
    _remove job
  else
    job_job.each jorq, {size:2}, ((job) -> _remove(job))
  return true

API.job.time = (cron,hhmm) -> # hhmm just allows a simple way to pass in daily 0500 (will also accept 500)
  res = {provided: cron, expanded: {}, next: {}}
  d = new Date()
  if cron is 'delete' or cron is 'remove' or cron is false
    res.cron = ''
  else if cron is 'yearly' or cron is 'annually'
    res.cron = '0 0 1 1 *'
  else if cron is 'monthly'
    res.cron = '0 0 1 * *'
  else if cron is 'weekly'
    res.cron = '0 0 * * 0'
  else if cron is 'daily' or cron is 'midnight'
    hhmm = hhmm.toString() if typeof hhmm is 'number'
    if typeof hhmm is 'string'
      if hhmm.length < 3
        cron = '0 ' + cron
      else if hhmm.length is 3
        cron = hhmm.substring(1,3) + ' ' + hhmm.substring(0,1)
      else if hhmm.length < 5
        cron = hhmm.substring(2,4) + ' ' + hhmm.substring(0,2).replace('0','') # replace a leading 0 with nothing, does not affect 00 because only replaces the first one
    else
      res.cron = '0 0'
    res.cron += ' * * *'
  else if cron is 'hourly'
    res.cron = '0 * * * *'
  else if cron.indexOf('minute') is 0 or cron is '*'
    res.cron = '* * * * *'
  parts = res.cron.split(' ')
  res.parts = 
    minute: parts[0] # 0-59 also allow comma separations e.g. 1,2,3,5-7,9. And * for everything
    hour: parts[1] # 0-23
    monthday: parts[2] # 1-31
    month: parts[3] # 1-12 or jan-dec or january-december
    weekday: parts[4] # 0-6 or sun-sat or sunday-saturday
  months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec']
  weekdays = ['su','mo','tu','we','th','fr','sa']
  for p of res.parts
    res.parts[p] = res.parts[p].replace(/ /g,'').toLowerCase()
    if res.parts[p] is '*'
      res.parts[p] = if p is 'minute' then '0-59' else if p is 'hour' then '0-23' else if p is 'monthday' then '1-31' else if p is month then '1-12' else '0-6'
    res.expanded[p] = []
    for val in res.parts[p].split(',')
      vd = val.split('-')
      left = vd[0]
      right = if vd.length is 2 then vd[1] else undefined
      for m of months
        left = m if left.indexOf(months[m]) is 0
        right = m if right? and right.indexOf(months[m]) is 0
      for w of weekdays
        left = w if left.indexOf(weekdays[w]) is 0
        right = w if right? and right.indexOf(weekdays[w]) is 0
      left = parseInt(left)
      res.expanded[p].push left
      res.next[p] = left if (d['get'+(if p is 'minute' then 'Minutes' else if p is 'hour' then 'Hours' else if p is 'monthday' then 'Date' else if p is 'month' then 'Month' else 'Day')]() + (if p is 'month' then 1 else 0)) < left
      if right?
        right = parseInt(right)
        while left < right
          left += 1
          res.expanded[p].push left
          res.next[p] ?= left if (d['get'+(if p is 'minute' then 'Minutes' else if p is 'hour' then 'Hours' else if p is 'monthday' then 'Date' else if p is 'month' then 'Month' else 'Day')]() + (if p is 'month' then 1 else 0)) < left
      # could add checking here to see if left or right is out of acceptable range for the given time part
    res.next[p] ?= res.expanded[p][0]
  nd = new Date(d.getFullYear(), res.next['month']-1, res.next['hour'], res.next['minute'])
  # if nd is not one of the allowed weekdays, roll it forward until it is
  # TODO handle year rollover
  res.next.timestamp = nd.valueOf()
  if nd.getDay() isnt res.next.weekday
    wdf = res.next.weekday-nd.getDay()
    res.next.timestamp += 86400000 * (if wdf < 0 then (7-wdf) else wdf)
  res.next.date = moment(res.next.timestamp, "x").format "YYYY-MM-DD HHmm.ss"
  res.now = Date.now()
  res.next.limit = res.next.timestamp - res.now
  return res
  
API.job.cron = (fn, args, title, cron, repeat=true) -> # repeat could be a timestamp to repeat until, or a time string for a simple way to create dailies, or a number of repeats, e.g. could do every day until ten have been done
  title ?= fn
  cron = API.job.time(cron,repeat) if typeof cron isnt 'object'
  if not fn?
    return job_process.fetch 'cron:*', true
  else if cron.parsed is '' and jp = job_process.get(title)?
    job_process.remove {group:title}
    return true
  else
    job_limit.insert {_id: p.group, group: p.group, limit: cron.next.limit}
    return job_process.insert {priority: 10000, group: title, function: fn, args: args, signature: API.job._sign(fn,args), cron: cron.parsed, repeat: repeat, limit: cron.next.limit}
  
API.job.limit = (limitms=1000,fn,args,group,refresh=0) -> # directly create a sync throttled process
  pr = {priority:10000, _id:Random.id(), group:(group ? fn), function: fn, args: args, signature: API.job._sign(fn,args), limit: limitms}
  if typeof refresh is 'number' and refresh isnt 0
    match = {must:[{term:{'signature.exact':pr.signature}},{range:{createdAt:{gt:Date.now() - refresh}}}], must_not:[{exists:{field:'_raw_result.error'}}]}
    jr = job_result.find match, true
  if not jr?
    rs = if typeof refresh is 'number' and refresh isnt 0 then job_processing.find({'signature.exact':pr.signature}, true)
    pr._id = if rs? then rs._id else job_process.insert pr
    while not jr?
      API.job.next() if not job_limit.get('STARTED')? and API.settings.job?.limit
      future = new Future()
      Meteor.setTimeout (() -> future.return()), limitms
      future.wait()
      limitms = 500 if not limitms? or limitms < 500
      jr = job_result.get pr._id
  return API.job.result jr

API.job.cap = (max,cap,group,fn,args) ->
  return undefined if not max? or not cap? or not group?
  # cap can be minute, hour, day, month in which case it will be the start of the current one
  if cap in ['minute','hour','day','month']
    date = new Date()
    beginning = new Date(date.getFullYear(), date.getMonth(), date.getDate(), date.getHours(), date.getMinutes()).valueOf() if cap is 'minute'
    beginning = new Date(date.getFullYear(), date.getMonth(), date.getDate(), date.getHours()).valueOf() if cap is 'hour'
    beginning = new Date(date.getFullYear(), date.getMonth(), date.getDate()).valueOf() if cap is 'day'
    beginning = new Date(date.getFullYear(), date.getMonth(), 1).valueOf() if cap is 'month'
  else
    # or cap should be a number in ms or a string starting with a number followed by ms/s/m/min/mins/minute/minutes/hour/hours/day/days
    try cp = parseInt(cap.replace('s','')) * 1000
    cp ?= parseInt(cap.replace('ms','')) if typeof cap is 'string' and 'ms' in cap
    cp ?= cap.replace('m','min') if typeof cap is 'string' and cap.indexOf('m') is cap.length-1
    if not cp? and typeof cap isnt 'number'
      cp = cap.toLowerCase().replace('s','').replace('ute','')
      format = if 'min' in cp then 'min' else if 'hour' in cp then 'hour' else 'day'
      back = parseInt(cp.replace(format,''))
      cp = back * (if format is 'min' then 60000 else if format is 'hour' then 360000 else 8640000)
    beginning = Date.now() - cp

  #job_cap.remove({group:group, createdAt:'<' + beginning}) if not API.settings.dev
  res = job_cap.find 'group.exact:' + group + ' AND createdAt:>' + beginning, {newest:false,size:1}
  earliest = if res.hits?.hits? and res.hits.hits.length then res.hits.hits[0]._source.createdAt else false
  capping = res.hits.total + 1
  capped = capping >= max
  job_cap.insert({group: group, beginning: beginning, earliest: earliest, capping: capping, max: max, cap: cap}) if not capped
  if fn?
    if capped
      future = new Future()
      Meteor.setTimeout (() -> future.return()), earliest - beginning
      future.wait()
      return API.job.cap max,cap,group,fn,args
    else
      if typeof fn is 'string'
        afn = if fn.indexOf('API.') is 0 then API else global
        afn = fn[p] for p in fn.replace('API.','').split('.')
        fn = afn
      try args = JSON.parse(args) if typeof args is 'string'
      return if _.isArray(args) then fn.apply(this, args) else fn args
  else
    return {capped: capped, capping: capping, beginning: beginning, earliest: earliest, wait: (if earliest then earliest - beginning else undefined)}

API.job.process = (proc) ->
  proc = job_process.get(proc) if typeof proc isnt 'object'
  return false if typeof proc isnt 'object'
  proc.args = JSON.stringify proc.args if proc.args? and typeof proc.args is 'object' # in case a process is passed directly with non-string args
  try proc._appid = process.env.APP_ID
  if proc._id? # should always be the case but check anyway
    return false if job_processing.get(proc._id)? # puts extra load on ES but may catch unnecessary duplicates
    job_process.remove proc._id
  proc._id = job_processing.insert proc # in case is a process with no ID, need to catch the ID
  API.log {msg:'Processing ' + proc._id,process:proc,level:'debug',function:'API.job.process'}
  fn = if proc.function.indexOf('API.') is 0 then API else global
  fn = fn[p] for p in proc.function.replace('API.','').split('.')

  try
    proc._raw_result = {}
    args = proc # default just send the whole process as the arg
    if proc.args?
      if typeof proc.args is 'string'
        try
          args = JSON.parse proc.args
        catch
          args = proc.args
      else
        args = proc.args
    if typeof args is 'object' and typeof proc.args is 'string' and proc.args.indexOf('[') is 0
      # save results keyed by function, so assuming functions produce results of same shape, they fit in index
      proc._raw_result[proc.function] = fn.apply this, args
    else
      proc._raw_result[proc.function] = fn args
  catch err
    proc._raw_result = {error: err.toString()}
    if err?
      proc._raw_result[proc.function] = if err.response? then err.response else err # catching the error response of a function is still technically a valid response
    API.log msg: 'Job process error', error: err, string: err.toString(), process: proc, level: 'debug'
    console.log(JSON.stringify err) if API.settings.log.level in ['debug','all']

  if typeof proc._raw_result?[proc.function] is 'boolean'
    proc._raw_result.bool = proc._raw_result[proc.function]
    delete proc._raw_result[proc.function]
  else if typeof proc._raw_result?[proc.function] is 'string'
    proc._raw_result.string = proc._raw_result[proc.function]
    delete proc._raw_result[proc.function]
  else if typeof proc._raw_result?[proc.function] is 'number'
    proc._raw_result.number = proc._raw_result[proc.function]
    delete proc._raw_result[proc.function]
  if not job_result.insert(proc)? and proc._raw_result?[proc.function]? # if this fails, stringify and save that way
    _original = proc._raw_result[proc.function]
    prs = JSON.stringify proc._raw_result[proc.function] # try saving as string then change it back
    proc._raw_result.string = prs
    delete proc._raw_result[proc.function]
    strung = job_result.insert proc
    delete proc._raw_result.string
    if not strung?
      proc._raw_result.attachment = new Buffer(prs).toString('base64')
      attd = job_result.insert proc
      delete proc._raw_result.attachment
      if not attd?
        proc._raw_result.error = 'Unable to save result'
        job_result.insert proc
    proc._raw_result[proc.function] = _original # put the original result back on, for return later

  job_processing.remove proc._id
  # keep repeating if repeat is true, or if it is a number greater than 0 and less than a datestamp of before around 16092017, or not a number (unlikely), or a datestamp number after now
  if proc.repeat and (typeof proc.repeat isnt 'number' or proc.repeat > Date.now() or proc.repeat < 1505519916316)
    proc.original ?= proc._id
    pn = _.clone proc
    pn.previous = proc._id
    delete pn._raw_result
    pn.repeat -= 1 if pn.repeat? and typeof pn.repeat is 'number' and pn.repeat < Date.now() # repeat can be a future timestamp to keep repeating until
    pn.counter ?= 1
    pn.counter += 1
    pn.limit = API.job.time(pn.cron) if pn.cron
    pn._id = Random.id()
    job_process.insert pn
  else if proc.order
    job_process.update {job: proc.job, order: proc.order+1}, {available:true}
  try
    job_job.each 'NOT done:true AND processes._id:' + proc._id, {_source:['processed','count']}, (job) ->
      job_job.update job._id, {processed:"+1"}
      if (job.processed ? 0) + 1 >= job.count
        API.job.complete job
  try
    if proc.callback
      cb = API
      cb = cb[c] for c in proc.callback.replace('API.','').split('.')
      cb null, proc # TODO should this go in timeout?
  return proc

API.job.next = () ->
  if job_limit.get('PAUSE')?
    return false
  if (API.settings.job?.concurrency ?= 1000000000) <= job_processing.count()
    API.log {msg:'Not running more jobs, max concurrency reached', _appid: process.env.APP_ID, function:'API.job.next'}
  else if (API.settings.job?.memory ? 1200000000) <= process.memoryUsage().rss
    API.log {msg:'Not running more jobs, job max memory reached', _appid: process.env.APP_ID, function:'API.job.next'}
  else
    console.log('Checking for jobs to run') if API.settings.dev or API.settings.job?.verbose?
    API.log {msg:'Checking for jobs to run', ignores: {groups:API.job._ignoregroups,ids:API.job._ignoreids}, function:'API.job.next', level:'all'}
    match = must_not:[{term:{available:false}}] # TODO check this will get matched properly to something where available = false
    match.must = API.settings.job.match if API.settings.job?.match?
    limits = job_limit.search 'NOT last:* AND expiresAt:>' + Date.now(), 1000
    if limits.hits?.hits?
      match.must_not.push({term: 'group.exact':g._source._id}) for g in limits.hits.hits
    p = job_process.find match, {sort:{priority:{order:'desc'}}, random:true} # TODO check if random sort works - may have to be more complex
    if p? and not job_processing.get(p._id)? # because job_process is searched, there can be a delay before it reflects deleted jobs, so accept this extra load on ES
      if p.limit?
        job_limit.insert {group:lm.group,last:lm.createdAt} if lm? and (API.settings.dev or API.settings.job?.verbose) # keep a history of limit counters until service restarts
        jl = job_limit.insert {_id:p.group, group:p.group, limit:p.limit, expiresAt:Date.now() + p.limit} # adding the limit here is just for info in status
      return API.job.process p
    else
      return false

API.job.reload = (q='*',list=false) ->
  # reload everything that was not done if q is true, or reload every process that
  # matches the job id if q is a job id, or reload every processing that matches the 
  # query if it is a query. Default is a * query which means everything already 
  # processing will be reloaded
  reloads = []
  _reload_job_processes = (job, injob=true) ->
    if typeof job.processes is 'object'
      processed = 0
      for p in job.processes
        try job_processing.remove(p._id)
        if (injob or job_job.search('processes._id:' + p._id, 0)?.hits?.total) and not job_result.exists(p._id) and not job_process.exists(p._id)
          try delete p.signature # some old jobs had bad signatures
          p.reloaded ?= []
          p.reloaded.push p.createdAt
          reloads.push p
        else if injob and job_result.exists(p._id)
          processed += 1
      API.job.complete(job) if injob and processed is job.count
  if q is true
    job_job.each 'NOT done:true', {size:2}, ((job) -> _reload_job_processes(job))
  else if q isnt '*' and job = job_job.get q
    _reload_job_processes job
  else
    job_processing.each q, (proc) -> _reload_job_processes {processes:[proc]}, false
  if reloads.length
    API.log 'Job runner reloading ' + reloads.length + ' jobs for ' + (if q is true then 'all jobs' else if typeof q is 'string' then 'query ' + q else ' complex query object')
    console.log 'doing reload for ' + reloads.length
    job_process.insert reloads
  return if list then _.pluck(reloads,'_id') else reloads.length

API.job._iid
API.job.start = (interval=API.settings.job?.interval ? 1000) ->
  future = new Future() # randomise start time so that cluster machines do not all start jobs at exactly the same time
  Meteor.setTimeout (() -> future.return()), Math.floor(Math.random()*interval+1)
  future.wait()
  API.log {msg: 'Starting job runner with interval ' + interval, _appid: process.env.APP_ID, function: 'API.job.start', level: 'debug'}
  olds = job_limit.get 'START_RELOAD'
  if not olds? or olds.createdAt < Date.now() - 300000
    job_limit.insert _id: 'START_RELOAD'
    API.job.reload()
    job_limit.remove '*'
  job_limit.insert _id: 'STARTED'
  #job_process.remove 'TEST'
  #job_processing.remove 'TEST'
  #job_result.remove 'TEST'
  #job_process.insert _id: 'TEST', repeat: true, function: 'API.test', priority: 8000, group: 'TEST', limit: 86400000 # daily system test
  API.job._iid ?= Meteor.setInterval API.job.next, interval

API.job.start() if not API.job._iid? and API.settings.job?.startup

API.job.running = () -> return (API.job._iid? or job_limit.get('STARTED')?) and not job_limit.get('PAUSE')?

API.job.stop = () -> job_limit.insert _id: 'PAUSE' # note that processes already processing will keep going, but no new ones will start

API.job.status = (filter='NOT group:TEST') ->
  res =
    running: API.job.running()
    jobs:
      count: job_job.count()
      done: job_job.count undefined, done:true
      waiting: 0
      oldest: {_id: jjo._id, createdAt: jjo.createdAt, created_date: jjo.created_date} if jjo = job_job.find('*', {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jjn._id, createdAt: jjn.createdAt, created_date: jjn.created_date} if jjn = job_job.find('*', true)
    processes:
      count: job_process.count(undefined,filter)
      oldest: {_id: jpo._id, createdAt: jpo.createdAt, created_date: jpo.created_date} if jpo = job_process.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jpn._id, createdAt: jpn.createdAt, created_date: jpn.created_date} if jpn = job_process.find(filter, true)
    processing:
      count: job_processing.count(undefined,filter)
      oldest: {_id: jpro._id, createdAt: jpro.createdAt, created_date: jpro.created_date} if jpro = job_processing.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jprn._id, createdAt: jprn.createdAt, created_date: jprn.created_date} if jprn = job_processing.find(filter, true)
    results:
      count: job_result.count(undefined,filter)
      oldest: {_id: jro._id, createdAt: jro.createdAt, created_date: jro.created_date} if jro = job_result.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jrn._id, createdAt: jrn.createdAt, created_date: jrn.created_date} if jrn = job_result.find(filter, true)
      cluster: job_result.terms('_cid')
  res.limits = {} # may not be worth reporting on limit index in new structure
  job_limit.each 'NOT last:*', (lm) -> res.limits[lm.group ? lm._id] = {date:lm.created_date,limit:lm.limit}
  job_job.each 'NOT done:true', {_source:['_id','count','processed']}, (j) -> res.jobs.waiting += (j.count - (j.processed ? 0))
  res.caps = {}
  job_cap.each '*', (cp) -> res.caps[cp.group ? cp._id] = {date:cp.created_date}
  return res

API.job.orphans = (remove=false,types=['process','result']) ->
  res = {}
  if 'process' in types
    res.process = found: 0, orphan: 0
    job_process.each '*', {_source:['_id']}, (p) -> 
      res.process.found += 1
      console.log(res) if res.process.found % 100 is 0
      if job_job.search('processes._id:' + p._id, 0).hits.total is 0
        res.process.orphan += 1
        job_process.remove(p._id) if remove
  if 'result' in types
    res.result = found: 0, orphan: 0
    job_result.each '*', {_source: ['_id']}, (r) -> 
      res.result.found += 1
      console.log(res) if res.result.found % 100 is 0
      if job_job.search('processes._id:' + r._id, 0).hits.total is 0
        res.result.orphan += 1
        job_result.remove(r._id) if remove
  return res

API.job.progress = (jobid) ->
  job = if typeof jobid is 'object' then jobid else job_job.get jobid
  progress = if job.done then 100 else if job.new then 0 else (job.processed ? 0)/job.count*100
  progress = 100 if progress > 100
  if progress is 100 and job.done isnt true
    API.job.complete job
  res = {running: API.job.running(), createdAt:job.createdAt, progress:progress, name:job.name, email:job.email, _id:job._id, new:job.new, count: job.count, processes: job.count, processed: job.processed ? 0}
  if progress isnt 100
    if res.running
      if Date.now() > (job.createdAt + (2000 * job.count)) and (Date.now() - (job.updatedAt ? 0)) > ((job.count - (job.processed ? 0)) * 2000)
        res.stuck = true
        res.missing = []
        res.waiting = 0
        res.processing = 0
        res.results = 0
        if typeof job.processes is 'object'
          for p in job.processes
            if job_processing.get(p._id) then res.processing += 1 else if job_process.get(p._id) then res.waiting += 1 else if job_result.get(p._id)? then res.results += 1 else res.missing.push(p._id)
        res.missed = res.missing.length
        if res.missed
          API.log 'Job progress checked for job ' + job._id + ', but processes are missing...' # TODO should this send an email warning to admin, to the job submitter, should it resubmit the missing processes?
    else
      API.log 'Job progress checked for job ' + job._id + ', but job runner is not running...' # TODO should this send an email warning to admin?
    if res.count is res.results
      res.progress = 100
      API.job.complete job
  return res

API.job.complete = (jobid='NOT done:true', set_done=true, run_complete=true, list=false, known=0) ->
  known = job_job.count(undefined, {done:true}) if known is true
  jobids = []
  _complete = (job) ->
    if job.done isnt true
      jobids.push job._id
      job_job.update(job._id, {done: true}) if set_done
      if run_complete
        job = job_job.get(job._id) if not job.processes? # we try not to pass round big process lists any more, but for passing to completion, need to get the full record
        try
          fn = if job.complete.indexOf('API.') is 0 then API else global
          fn = fn[f] for f in job.complete.replace('API.','').split('.')
          fn job
        catch
          if job.group isnt 'JOBTEST'
            text = 'Job ' + (if job.name then job.name else job._id) + ' is complete.'
            API.mail.send to: (job.email ? API.accounts.retrieve(job.user)?.emails[0].address), subject: text, text: text
  job = if jobid is true then 'NOT done:true' else if typeof jobid is 'object' then jobid else job_job.get jobid
  if typeof job is 'object'
    _complete job
    return true
  else
    job_job.each (job ? jobid), {size:2}, ((job) -> _complete(job))
    return if list then jobids else jobids.length + known

API.job.rerun = (jobid,uid) ->
  job = job_job.get jobid
  job.user = uid if uid
  job.refresh = 0
  job._id = job_job.insert {new:true, user:job.user, processed: 0}
  Meteor.setTimeout (() -> API.job.create job), 2
  return job:job._id

API.job.result = (jr,full) ->
  jr = job_result.get(jr) if typeof jr is 'string'
  if full?
    return jr ? {}
  else
    if jr?._raw_result?[jr.function]?
      return jr._raw_result[jr.function]
    else if jr?._raw_result?.string? or jr?._raw_result?.attachment?
      dc = if jr._raw_result.attachment? then new Buffer(jr._raw_result.attachment,'base64').toString('utf-8') else jr._raw_result.string
      if dc.indexOf('[') is 0 or dc.indexOf('{') is 0
        try
          return JSON.parse dc
      return dc
    else if jr?._raw_result?.bool?
      return jr._raw_result.bool
    else if jr?._raw_result?.number?
      return jr._raw_result.number
    else if jr?._raw_result?.error
      return jr._raw_result.error
    else
      return {}

API.job.results = (jobid,full) ->
  results = []
  try
    for ji in job_job.get(jobid).processes
      results.push API.job.result ji._id, full
  return results




################################################################################

API.add 'job/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.job.test this.queryParams.verbose, not this.queryParams.cleanup?

API.job._test = {
  counter: 0,
  times: [],
  diffs: [],
  run: () ->
    API.job._test.times.push(Date.now())
    if API.job._test.times.length > 1
      API.job._test.diffs.push API.job._test.times[API.job._test.times.length-1] - API.job._test.times[API.job._test.times.length-2]
    API.job._test.counter += 1
}
API.job.test = (verbose,cleanup=true) ->
  console.log('Starting job test') if API.settings.dev

  result = {passed:[],failed:[]}

  job_limit.remove group: 'JOBTEST'
  job_job.remove group: 'JOBTEST'
  job_process.remove group: 'JOBTEST'
  job_processing.remove group: 'JOBTEST'
  job_result.remove group: 'JOBTEST'

  tests = []

  if API.settings.job?.startup is true
    tests.push () ->
      result.limitstart = Date.now()
      result.diffs = []
      result.first = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST'
      tmr = Date.now()
      result.diffs.push tmr - result.limitstart
      result.second = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST'
      tmr2 = Date.now()
      result.diffs.push tmr2 - tmr
      result.third = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST'
      result.limitend = Date.now()
      result.diffs.push result.limitend - tmr2
      result.limitdifference = result.limitend - result.limitstart
      return result.first is true and result.second is true and result.third is true and result.limitdifference > 4500
    tests.push () ->
      result.stlimitstart = Date.now()
      API.job._test.counter = 0
      API.job._test.times = []
      API.job._test.diffs = []
      Meteor.setTimeout (() -> API.job.limit 1500, 'API.job._test.run', undefined, 'JOBTEST'), 1
      Meteor.setTimeout (() -> API.job.limit 1500, 'API.job._test.run', undefined, 'JOBTEST'), 1
      Meteor.setTimeout (() -> API.job.limit 1500, 'API.job._test.run', undefined, 'JOBTEST'), 1
      while API.job._test.counter isnt 3
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 1000
        future.wait()
      result.sttimes = API.job._test.times
      result.stdiffs = API.job._test.diffs
      result.stlimitend = Date.now()
      result.stlimitdifference = result.stlimitend - result.stlimitstart
      API.job._test.counter = 0
      API.job._test.times = []
      API.job._test.diffs = []
      return result.stlimitdifference > 4500
    tests.push () ->
      result.limits = job_limit.search({group:"JOBTEST"},{sort:{createdAt:{order:'asc'}}})?.hits?.hits
      result.greater = true
      result.lmdiffs = []
      ts = true
      for lm in result.limits
        if lm._source.last?
          if ts isnt true
            diff = lm._source.last - ts
            result.lmdiffs.push diff
            result.greater = diff > 1500
          ts = lm._source.last
      return result.greater is true
    tests.push () ->
      result.rlimitstart = Date.now()
      result.rfirst = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST', 1000000
      result.rsecond = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST', 1000000
      result.rlimitend = Date.now()
      result.rlimitdifference = result.rlimitend - result.rlimitstart
      return result.rfirst is true and result.rsecond is true and result.rlimitdifference < 1500
    tests.push () ->
      result.job = API.job.create {group: 'JOBTEST', refresh: true, processes:['API.job.running','API.job.running']}
      return result.job._id?
    tests.push () ->
      while result.progress?.progress isnt 100
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 1500
        future.wait()
        result.progress = API.job.progress result.job
        return true if result.progress.progress is 100
    tests.push () ->
      result.results = API.job.results result.job._id
      return _.isEqual result.results, [true,true]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  if cleanup
    job_job.remove group: 'JOBTEST'
    job_process.remove group: 'JOBTEST'
    job_processing.remove group: 'JOBTEST'
    job_result.remove group: 'JOBTEST'
    job_limit.remove group: 'JOBTEST'

  console.log('Ending job test') if API.settings.dev

  return result

