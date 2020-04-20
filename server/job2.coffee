
'''
import { Random } from 'meteor/random'
import Future from 'fibers/future'
import crypto from 'crypto'
import moment from 'moment'

API.job = {}

# TODO could list _.keys process.env and for any starting with NODDY_SETTINGS_ use their remaining name to update the running settings
if API.settings.job?.startup isnt true and (process.env.NODDY_SETTINGS_JOB_STARTUP is true or (process.env.NODDY_SETTINGS_JOB_STARTUP? and process.env.NODDY_SETTINGS_JOB_STARTUP.toLowerCase() is 'true'))
  API.log 'Job runner altering job startup setting to true based on provided JOB_STARTUP env setting'
  API.settings.job ?= {}
  API.settings.job.startup = true

@job_job = new API.collection index: API.settings.es.index + "_job", type: "job"
@job_process = new API.collection index: API.settings.es.index + "_job", type: "process"
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
        j = {user:this.userId}
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
          job.progress ?= API.job.progress(job) if this.queryParams.progress
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
      return if not API.job.allowed(this.urlParams.job,this.user) then 401 else API.job.remove this.urlParams.job

API.add 'job/:job/progress', get: () -> return if not job = job_job.get(this.urlParams.job) then 404 else API.job.progress job

API.add 'job/:job/complete',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.complete this.urlParams.job

API.add 'job/:job/results',
  get:
    # authRequired: true this has to be open if people are going to share jobs, but then what about jobs is closed?
    action: () ->
      job = job_job.get this.urlParams.job
      # return 401 if not API.job.allowed job,this.user
      return API.job.results this.urlParams.job
API.add 'job/:job/results.csv',
  get:
    # authRequired: true this has to be open if people are going to share jobs, but then what about jobs is closed?
    action: () ->
      # return 401 if not API.job.allowed job,this.user
      return if not job = job_job.get(this.urlParams.job) then 404 else API.convert.json2csv2response this, API.job.results(this.urlParams.job), (if job.name then job.name.split('.')[0].replace(/ /g,'_') + '_results' else 'results')+".csv"

API.add 'job/:job/rerun',
  get:
    authOptional: true # TODO decide proper permissions for this and pass uid to job.rerun if suitable
    action: () -> return API.job.rerun(this.urlParams.job, this.userId)

API.add 'job/:job/reload',
  get:
    authOptional: true # TODO decide proper permissions for this
    action: () -> return API.job.reload(this.urlParams.job,this.queryParams.list)

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
        return count: job_job.count(), done: job_job.count undefined, {progress: 100}

API.add 'job/jobs/:email',
  get:
    authRequired: not API.settings.dev
    action: () ->
      if this.user? and not API.accounts.auth('job.admin',this.user) and this.user.emails[0].address isnt this.urlParams.email
        return 401
      else
        results = []
        done = 0
        job_job.each {email:this.urlParams.email}, (if this.queryParams.processes then {size:this.queryParams.size ? 2} else {_source: {exclude:['processes']}}), ((job) -> done += if job.progress is 100 then 1 else 0; results.push job)
        return total: results.length, done: done, jobs: results

API.add 'job/processes',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_process.search this.queryParams
      else
        return count: job_process.count()

API.add 'job/results',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_process.search this.queryParams, restrict: [exists: field: 'result']
      else
        return count: job_process.count undefined, exists: field: 'result'

API.add 'job/result/:_id',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.result this.urlParams._id

API.add 'job/start',
  get:
    roleRequired: 'job.admin'
    action: () -> API.job.start(); return true
API.add 'job/stop',
  get:
    roleRequired: 'job.admin'
    action: () -> API.job.stop(); return true
API.add 'job/status', get: () -> return API.job.status()



API.job.sign = (fn='', args, ignores=['apikey','_'], lower=true) ->
  if typeof fn isnt 'string'
    args = fn
    fn = ''
  try
    args = _.clone args
    for k in ignores
      delete args[k]
  try fn += (if fn is '' then '' else '_') + JSON.stringify(args).split('').sort().join('')
  fn = fn.toLowerCase() if lower
  return crypto.createHash('md5').update(encodeURIComponent(fn), 'utf8').digest('base64') # TODO change this to 'hex' but first need to convert stored ones

API.job.allowed = (job,uacc) ->
  job = job_job.get(job) if typeof job is 'string'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'
  return if not job or not uacc then false else job.user is uacc._id or API.accounts.auth 'job.admin',uacc

API.job.create = (job) ->
  job = job_job.get(job) if typeof job isnt 'object'
  job.refresh = 0 if job.refresh is true
  job.refresh = parseInt(job.refresh) if typeof job.refresh is 'string'
  delete job.refresh if typeof job.refresh isnt 'number' # should there be a default refresh number?
  job.repeat = 0 if job.repeat is true
  job.processes ?= []
  job.count = job.processes.length
  job.priority ?= if job.count <= 10 then 11 - job.count else 0 # set high priority for short jobs more likely to be from a UI
  job.args = JSON.stringify(job.args) if job.args? and typeof job.args isnt 'string' # store args as string so can handle multiple types
  # A job can also set the "service" value to indicate which service it belongs to, so that queries about jobs only related to the service can be performed
  # A job can have ordered:true if so, processes will only be created once their predecessor is complete, so ordered processes could use previous results
  job._id = job_job.insert(job) if not job._id?
  imports = []
  for i of job.processes
    # processes list can contain string name of function to run, or else assumed to be different args for the overall job function
    proc = if typeof job.processes[i] is 'string' and job.processes[i].indexOf('API.') is 0 then {function: job.processes[i]} else (if typeof job.processes[i] is 'object' and job.processes[i].function? then job.processes[i] else {function: job.function, args:job.processes[i]})
    proc.service ?= job.service # just for useful info, if provided by the service that creates the job
    proc.priority ?= job.priority # higher priority runs sooner, otherwise runs at random - who can set this?
    proc.function ?= job.function # string name of the function to run
    proc.args ?= job.args # args to pass to the function, if any
    proc.args = JSON.stringify(proc.args) if proc.args? and typeof proc.args isnt 'string' # args stored in index as string so can handle different types
    proc.ordered ?= job.ordered # only run the processes in the order they are listed in the job
    # Repeats until counter reaches repeat number, or if repeat is zero, forever. Or if repeat is big enough to be a date, repeats until that date
    # For a process that repeats AND is in an ordered job, it will complete all repeats before kicking off the next process
    # If it repeats and has a limit, it repeats at that limit rate
    proc.repeat ?= job.repeat # The repeat option is probably best set per process than per job
    proc.limit ?= job.limit # option number of ms to wait before starting another one
    proc.group ?= job.group ? proc.function # group name string necessary for limit to compare against
    proc.callback ?= job.callback # optional callback name string per job or process, will call when process completes. Processes do return too, so either way is good
    proc.signature = API.job.sign proc.function, proc.args # combines with refresh to decide if need to run process or just pick up result from a same recent process
    proc._id ?= Random.id()
    proc.depends = job.processes[i-1]._id if proc.ordered and parseInt(i) isnt 0

    if job.refresh is 0 or proc.callback? or proc.ordered? or proc.repeat?
      imports.push proc
    else
      match = {must:[{term:{'signature.exact':proc.signature}}], must_not:[{exists:{field:'result.error'}},{exists:{field:'repeat'}}]}
      if typeof job.refresh is 'number' and job.refresh isnt 0
        d = new Date()
        match.must.push {range:{createdAt:{gt:d.setDate(d.getDate() - job.refresh)}}}
      rs = job_process.find(match, true) ? job_process.find({'signature.exact':proc.signature}, true)
      if rs then proc._id = rs._id else imports.push proc
    job.processes[i] = proc._id

  job_process.insert(imports) if imports.length
  job_job.update job._id, job
  return job

API.job.process = (proc) ->
  proc = job_process.get(proc) if typeof proc isnt 'object'
  proc.args = JSON.stringify proc.args if proc.args? and typeof proc.args is 'object' # in case a process is passed directly with non-string args
  fn = if proc.function.indexOf('API.') is 0 then API else global
  fn = fn[p] for p in proc.function.replace('API.','').split('.')
  try
    args = proc # default just send the whole process as the arg
    if proc.args?
      try
        args = JSON.parse proc.args
      catch
        args = proc.args
    if typeof args is 'object' and typeof proc.args is 'string' and proc.args.indexOf('[') is 0
      proc.result = fn.apply this, args
    else
      proc.result = fn args
  catch err
    proc.error = err.toString()

  API.job.save proc

  # keep repeating if repeat is present, or if it is a number greater than 0 and less than a datestamp of before around 16092017, or not a number (unlikely), or a datestamp number after now
  if proc.repeat? and (proc.repeat > Date.now() or (proc.repeat < 1505519916316 and (not proc.counter? or proc.repeat > proc.counter)))
    proc.counter ?= 0
    pr = _.clone proc
    pr.original ?= proc._id
    pr.previous = proc._id
    pr.counter += 1
    pr.limit = API.job.time(pr.cron) if pr.cron
    delete pr._id
    job_process.insert pr
  if proc.ordered and nj = job_process.get depends: proc._id
    Meteor.setImmediate (() -> API.job.process nj)
  else
    Meteor.setImmediate(() -> API.job.next())
  try
    if proc.callback
      cb = API
      cb = cb[c] for c in proc.callback.replace('API.','').split('.')
      cb null, proc.result ? proc.error
  return proc.result ? proc.error

API.job.limit = (limitms=1000,fn,args,group) ->
  pr = {priority:10000, group:(group ? fn), function: fn, args: args, signature: API.job.sign(fn,args), limit: limitms}
  jp = job_process.find {'signature.exact':pr.signature}, true
  if jp? then pr = jp else pr._id =  job_process.insert pr
  while not pr.result?
    API.job.next(pr.group) if not API.job.running()
    future = new Future()
    Meteor.setTimeout (() -> future.return()), Math.floor(limitms/2)
    future.wait()
    pr = job_process.get pr._id
  return API.job.result pr

API.job.next = (group) ->
  if (API.job.running() and API.settings.job?.startup) or group?
    match = must_not:[{exists:{field:'depends'}},{exists:{field:'result'}}]
    match.must = if API.settings.job?.match? then API.settings.job.match else [] # allows to make this instance run only certain kinds of process
    match.must.push({term: 'group.exact':group}) if group?
    job_limit.each 'expiresAt:>' + Date.now(), (jl) -> match.must_not.push({term: 'group.exact':jl._id})
    p = job_process.find match, {sort:{priority:{order:'desc'}}, random:true} # TODO check if random sort works - may have to be more complex
    if p? and not job_limit.get(p._id)? and (not p.group? or not job_limit.get(p.group)?) # just make sure one hasn't been created during the search interim
      job_limit.insert({_id:p.group, group:p.group, limit:p.limit, expiresAt:Date.now() + p.limit}) if p.limit? # group limit
      job_limit.insert({_id:p._id, group:p._id, limit:86400000, expiresAt:Date.now() + 86400000}) # limit each process to make sure they don't get picked up by another runner in the cluster, at least for a day or until restart
      API.job.process p

API.job.progress = (jobid='NOT progress:100') ->
  _progress = (job) ->
    res = running: API.job.running(), processed: 0, waiting: 0
    if job.progress isnt 100
      for p in job.processes
        res.processed += 1 if job_process.get(p._id).result? then res.processed += 1 else res.waiting += 1
      res.progress = Math.floor res.processed/res.processes.length*100
      Meteor.setImmediate(() -> API.job.complete(job)) if res.progress is 100
      job_job.update job._id, progress: res.progress
    else
      res.processed = res.processes.length
      res.progress = 100
    return res
  job = if jobid is true then 'NOT progress:100' else if typeof jobid is 'object' then jobid else job_job.get jobid
  return if typeof job is 'object' and job._id? then _progress(job) else job_job.each (job), {size:2}, ((job) -> _progress(job))

API.job.complete = (jobid) ->
  job = if typeof jobid is 'object' then jobid else job_job.get jobid
  try
    fn = if job.complete.indexOf('API.') is 0 then API else global
    fn = fn[f] for f in job.complete.replace('API.','').split('.')
    fn job
    return true
  catch
    if job.group isnt 'JOBTEST'
      text = 'Job ' + (if job.name then job.name else job._id) + ' is complete.'
      API.mail.send to: (job.email ? API.accounts.retrieve(job.user)?.emails[0].address), subject: text, text: text
    return false

API.job.rerun = (jobid,uid) -> # TODO this will need changed
  job = job_job.get jobid
  job.user = uid if uid
  job.refresh = 0
  job._id = job_job.insert {user:job.user}
  Meteor.setImmediate (() -> API.job.create job)
  return job:job._id

API.job.save = (proc) ->
  if proc.error?
    job_process.update proc._id, result: error: proc.error
  else
    _raw_result = {}
    if typeof proc.result in ['boolean','string','number']
      _raw_result[typeof proc.result] = proc.result
      job_process.update proc._id, result: _raw_result
    else
      _raw_result[proc.function] = proc.result
      if not job_process.update(proc._id, result:_raw_result)? # check how to actually identify a failed update
        delete _raw_result[proc.function]
        _raw_result.string = JSON.stringify proc.result
        if not job_process.update(proc._id, result:_raw_result)?
          delete _raw_result.string
          _raw_result.attachment = new Buffer(JSON.stringify(proc.result)).toString('base64')
          if not job_process.update(proc._id, result:_raw_result)?
            job_process.update proc._id, result: error: proc.error
  job_process.remove proc._id
  job_limit.remove proc._id

API.job.result = (jr,full) ->
  jr = job_process.get(jr) if typeof jr is 'string'
  if full?
    return jr ? {}
  else if jr?.result?._raw_result?[jr.function]?
    return jr.result._raw_result[jr.function]
  else if jr?.result?._raw_result?.string? or jr?.result?._raw_result?.attachment?
    dc = if jr.result._raw_result.attachment? then new Buffer(jr.result._raw_result.attachment,'base64').toString('utf-8') else jr.result._raw_result.string
    if dc.indexOf('[') is 0 or dc.indexOf('{') is 0
      try
        return JSON.parse dc
    return dc
  else
    return jr?.result?._raw_result?.boolean ? jr?.result?._raw_result?.number ? jr?.result?.error ? {}

API.job.results = (jobid,full) ->
  results = []
  try
    for ji in job_job.get(jobid).processes
      results.push API.job.result ji, full
  return results

API.job.remove = (jorq) ->
  _remove = (job) ->
    try
      for p in job.processes
        if job_job.search('NOT _id:' + job._id + ' AND processes:' + p).hits.total is 0
          try job_limit.remove p
          try job_process.remove p
    job_job.remove job._id
  if (typeof jorq is 'object' and jorq._id?) or job_job.exists(jorq)
    job = if typeof jorq is 'object' then jorq else job_job.get jorq
    _remove job
    return true
  else
    return job_job.each jorq, {size:2}, ((job) -> _remove(job))

API.job.status = (filter='NOT group:TEST') ->
  res =
    running: API.job.running()
    jobs:
      count: job_job.count()
      done: job_job.count undefined, progress:100
      oldest: {_id: jjo._id, createdAt: jjo.createdAt, created_date: jjo.created_date} if jjo = job_job.find('*', {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jjn._id, createdAt: jjn.createdAt, created_date: jjn.created_date} if jjn = job_job.find('*', true)
    processes:
      count: job_process.count undefined, filter
      done: job_process.count undefined, exists: field: 'result'
      oldest: {_id: jpo._id, createdAt: jpo.createdAt, created_date: jpo.created_date} if jpo = job_process.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jpn._id, createdAt: jpn.createdAt, created_date: jpn.created_date} if jpn = job_process.find(filter, true)
  res.limits = {count: 0}
  job_limit.each '*', (lm) -> res.limits[lm.group ? lm._id] = {date:lm.created_date,limit:lm.limit}; res.limits.count += 1
  res.caps = {}
  job_cap.each '*', (cp) -> res.caps[cp.group ? cp._id] = {date:cp.created_date}
  return res

API.job.stop = () -> job_limit.remove 'RUNNING'

API.job._checked_running = false
API.job.running = () ->
  if API.job._checked_running isnt false and API.job._checked_running + 60000 > Date.now()
    return true
  else if job_limit.get('RUNNING')?
    API.job._checked_running = Date.now()
    return true
  else
    return false

_JSI = undefined
API.job.start = () ->
  if not API.job.running()
    job_limit.remove '*'
    job_limit.insert _id: 'RUNNING'
  if API.settings.job?.startup and _JSI is undefined
    _JSI = Meteor.setInterval (() -> API.job.next()), 1000
    Meteor.setInterval (() -> API.job.progress()), 10000
API.job.start()

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

  #job_cap.remove({group:group, createdAt:'<' + beginning})
  res = job_cap.find 'group.exact:' + group + ' AND createdAt:>' + beginning, {newest:false,size:1}
  earliest = if res.hits?.hits? and res.hits.hits.length then res.hits.hits[0]._source.createdAt else false
  capping = res.hits.total
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

API.job.cron = (fn, args, title, cron, repeat=0) -> # repeat could be a timestamp to repeat until, or a time string for a simple way to create dailies, or a number of repeats, e.g. could do every day until ten have been done
  title ?= fn
  cron = API.job.time(cron,repeat) if typeof cron isnt 'object'
  if not fn?
    return job_process.fetch 'cron:*', true
  else if cron.parsed is '' and jp = job_process.get(title)?
    job_process.remove {group:title}
    return true
  else
    job_limit.insert {_id: p.group, group: p.group, limit: cron.next.limit}
    return job_process.insert {priority: 1000000, group: title, function: fn, args: args, signature: API.job.sign(fn,args), cron: cron.parsed, repeat: repeat, limit: cron.next.limit}

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
    job_limit.remove group: 'JOBTEST'

  console.log('Ending job test') if API.settings.dev

  return result
'''
