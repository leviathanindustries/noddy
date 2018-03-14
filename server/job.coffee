

import { Random } from 'meteor/random'
import Future from 'fibers/future'
import moment from 'moment'

API.job = {}

@job_job = new API.collection index: API.settings.es.index + "_job", type: "job"
@job_process = new API.collection index: API.settings.es.index + "_job", type: "process"
@job_processing = new API.collection index: API.settings.es.index + "_job", type: "processing"
@job_result = new API.collection index: API.settings.es.index + "_job", type: "result"
@job_limit = new API.collection index: API.settings.es.index + "_job", type: "limit"

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
        j = {new:true, user:this.userId}
        j._id = job_job.insert j # jobs created to provide immediate info to user
        j.processes = if this.request.body.processes then this.request.body.processes else this.request.body
        j.refresh ?= this.queryParams.refresh
        Meteor.setTimeout (() -> API.job.create j), 5
        return job:j._id

API.add 'job/:job',
  get:
    authRequired: true
    action: () ->
      if job = job_job.get this.urlParams.job
        if not API.job.allowed job, this.user
          return 401
        else
          job.progress = API.job.progress job
          return job
      else
        return 404
  delete:
    roleRequired: 'job.user' # who if anyone can remove jobs?
    action: () -> return if not API.job.allowed(this.urlParams.job,this.user) then 401 else job_job.remove this.urlParams.job

API.add 'job/:job/progress', get: () -> return if not job = job_job.get(this.urlParams.job) then 404 else API.job.progress job, this.queryParams.reload?

API.add 'job/:job/results',
  get:
    # authRequired: true this has to be open if people are going to share jobs, but then what about jobs is closed?
    action: () ->
      job = job_job.get this.urlParams.job
      # return 401 if not API.job.allowed job,this.user
      return 404 if not job
      res = API.job.results this.urlParams.job, this.queryParams.full
      if this.queryParams.format is 'csv'
        res = API.convert.json2csv undefined,undefined,res
        this.response.writeHead 200,
          'Content-disposition': "attachment; filename="+(if job.name then job.name.split('.')[0].replace(/ /g,'_') + '_results' else 'results')+".csv",
          'Content-type': 'text/csv',
          'Content-length': res.length
        this.response.end res
        this.done()
      else
        return res

API.add 'job/:job/rerun',
  get:
    authOptional: true # TODO decide proper permissions for this and pass uid to job.rerun if suitable
    action: () -> return job: API.job.rerun(this.urlParams.job, this.userId)

API.add 'job/:job/reload',
  get:
    authOptional: true # TODO decide proper permissions for this and pass uid to job.rerun if suitable
    action: () -> return job: API.job.reload(this.urlParams.job)

API.add 'job/jobs',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_job.search this.queryParams
      else
        return data: job_job.count()

API.add 'job/jobs/:email',
  get:
    authRequired: not API.settings.dev
    action: () ->
      if not API.accounts.auth('job.admin',this.user) and this.user.emails[0].address isnt this.urlParams.email
        return 401
      else
        results = []
        job_job.each {email:this.urlParams.email}, ((job) -> job.processes = job.processes.length; results.push job)
        return total:results.length, jobs: results

API.add 'job/results',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_result.search this.queryParams
      else
        return data: job_result.count()

API.add 'job/limits',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_limit.search this.queryParams
      else
        return data: job_limit.count()

API.add 'job/processes',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_process.search this.queryParams
      else
        return data: job_process.count()

API.add 'job/processing',
  get:
    authOptional: true
    action: () ->
      if this.user? and API.accounts.auth 'root', this.user
        return job_processing.search this.queryParams
      else
        return data: job_processing.count()

API.add 'job/processing/reload',
  get:
    roleRequired: if API.settings.dev then false else 'job.admin'
    action: () -> return API.job.reload()

API.add 'job/clear/:which',
  get:
    authRequired: 'root'
    action: () ->
      if this.urlParams.which is 'results'
        return job_result.remove if _.isEmpty(this.queryParams) then '*' else this.queryParams
      else if this.urlParams.which is 'processes'
        res = job_process.remove if _.isEmpty(this.queryParams) then '*' else this.queryParams
        job_process.insert _id: 'STUCK', repeat: true, function: 'API.job.stuck', priority: 1, group: 'API.job.stuck', limit: 900000
        return res
      else if this.urlParams.which is 'processing'
        return job_processing.remove if _.isEmpty(this.queryParams) then '*' else this.queryParams
      else if this.urlParams.which is 'jobs'
        return job_job.remove if _.isEmpty(this.queryParams) then '*' else this.queryParams
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



API.job.allowed = (job,uacc) ->
  job = job_job.get(job) if typeof job is 'string'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'
  return if not job or not uacc then false else job.user is uacc._id or API.accounts.auth 'job.admin',uacc

API.job.create = (job) ->
  job = job_job.get(job) if typeof job isnt 'object'
  # A job can set the "service" value to indicate which service it belongs to, so that queries about jobs only related to the service can be performed
  # NOTE there is a process priority field which can be set from the job too - how to decide who can set priorities?
  job.priority ?= if job.processes.length <= 10 then 11 - job.processes.length else 0 # set high priority for short jobs more likely to be from a UI
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
      job.refresh = true # an ordered job has to use fresh results, so that it uses results created in order (else why bother ordering it?)
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
    proc.signature = encodeURIComponent proc.function + '_' + proc.args # combines with refresh to decide if need to run process or just pick up result from a same recent process

    job.refresh = parseInt(job.refresh) if typeof job.refresh is 'string'
    if job.refresh is true or job.refresh is 0 or proc.callback? or proc.repeat?
      proc._id = Random.id()
      imports.push proc
    else
      match = {must:[{term:{'signature.exact':proc.signature}}], must_not:[{exists:{field:'_raw_result.error'}}]}
      try
        if typeof job.refresh is 'number' and job.refresh isnt 0
          d = new Date()
          match.must.push {range:{createdAt:{gt:d.setDate(d.getDate() - job.refresh)}}}
      rs = job_result.find match, true
      ofnd = {'signature.exact':proc.signature}
      rs = job_processing.find(ofnd, true) if not rs?
      rs = job_process.find(ofnd, true) if not rs?
      if rs
        proc._id = rs._id
      else
        proc._id = Random.id()
        imports.push proc

    job.processes[i] = proc

  if imports.length
    job_process.import(imports)
    job_process.refresh()

  # NOTE job can also have a "complete" function string name, which will be called when API.job.progress hits 100%, see below
  # the "complete" function will receive the whole job object as the only argument (so can look up results by the process IDs)
  job.done = job.processes.length is 0 # bit pointless submitting empty jobs, but theoretically possible. Could make impossible...
  job.new = false
  if job._id
    job_job.update job._id, job
  else
    job._id = job_job.insert job
  return job

API.job.limit = (limitms,fn,args,group,refresh=0) -> # directly create a sync throttled process
  pr = {priority:10000,_id:Random.id(),group:(group ? fn), function: fn, args: args, signature: encodeURIComponent(fn + '_' + args), limit: limitms}
  if typeof refresh is 'number' and refresh isnt 0
    match = {must:[{term:{'signature.exact':pr.signature}},{range:{createdAt:{gt:Date.now() - refresh}}}], must_not:[{exists:{field:'_raw_result.error'}}]}
    jr = job_result.find match, true
  if not jr?
    rs = if typeof refresh is 'number' and refresh isnt 0 then job_processing.find({'signature.exact':pr.signature}, true)
    if rs?
      pr._id = rs._id
    else
      jp = job_process.insert pr
    while not jr?
      future = new Future()
      Meteor.setTimeout (() -> future.return()), limitms
      future.wait()
      jr = job_result.get pr._id
  return API.job.result jr

API.job.process = (proc) ->
  proc = job_process.get(proc) if typeof proc isnt 'object'
  return false if typeof proc isnt 'object'
  proc.args = JSON.stringify proc.args if proc.args? and typeof proc.args is 'object' # in case a process is passed directly with non-string args
  try proc._cid = process.env.CID
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
  if proc.repeat
    proc.original ?= proc._id
    pn = JSON.parse(JSON.stringify(proc))
    pn.previous = proc._id
    delete pn._raw_result
    pn.repeat -= 1 if pn.repeat? and typeof pn.repeat is 'number'
    pn.counter ?= 1
    pn.counter += 1
    pn._id = Random.id()
    job_process.insert pn
  else if proc.order
    job_process.update {job: proc.job, order: proc.order+1}, {available:true}
  # TODO trigger a job progress check in a way that does not cause memory creep
  if proc.callback
    cb = API
    cb = cb[c] for c in proc.callback.replace('API.','').split('.')
    cb null, proc # TODO should this go in timeout?
  return proc

API.job._ignoregroups = {}
API.job._ignoreids = {}
API.job.next = () ->
  if job_limit.get('PAUSE')?
    return false
  now = Date.now()
  for k, v of API.job._ignoregroups
    if v <= now
      delete API.job._ignoregroups[k]
  for s, t of API.job._ignoreids
    if t <= now
      delete API.job._ignoreids[s]
  if (API.settings.job?.concurrency ?= 1000000000) <= job_processing.count()
    API.log {msg:'Not running more jobs, job max concurrency reached', _cid: process.env.CID, _appid: process.env.APP_ID, function:'API.job.next'}
  else if (API.settings.job?.memory ? 1300000000) <= process.memoryUsage().rss
    # TODO should check why this is happening, is it memory leak or just legit usage while running lots of jobs?
    # and if legit and being hit on every available machine in the cluster, should trigger alert to start more cluster machines?
    API.log {msg:'Not running more jobs, job max memory reached', _cid: process.env.CID, _appid: process.env.APP_ID, function:'API.job.next'}
  else
    API.log {msg:'Checking for jobs to run',ignore:API.job._ignoregroups,function:'API.job.next',level:'all'}
    match = must_not:[{term:{available:false}}] # TODO check this will get matched properly to something where available = false
    match.must_not.push({term: 'group.exact':g}) for g of API.job._ignoregroups
    match.must_not.push({term: '_id.exact':m}) for m of API.job._ignoreids
    #console.log(JSON.stringify match) if API.settings.dev
    p = job_process.find match, {sort:{priority:{order:'desc'}}, random:true} # TODO check if random sort works - may have to be more complex
    if p?
      if job_processing.get(p._id)? # because job_process is searched, there can be a delay before it reflects deleted jobs, so accept this extra load on ES
        API.job._ignoreids[p._id] = now + API.settings.job?.interval ? 1000
        return API.job.next()
      else if p.limit?
        lm = job_limit.get p.group
        if lm? and lm.createdAt + p.limit > now
          if not API.job._ignoregroups[p.group]?
            API.job._ignoregroups[p.group] = lm.createdAt + p.limit
            return API.job.next()
          else
            return false
        else
          job_limit.insert {group:lm.group,last:lm.createdAt} if lm? and API.settings.dev # keep a history of limit counters until service restarts
          jl = job_limit.insert {_id:p.group,group:p.group,limit:p.limit} # adding the limit here is just for info in status
          API.job._ignoreids[p._id] = now + API.settings.job?.interval ? 1000
          return API.job.process p
      else
        API.job._ignoreids[p._id] = now + API.settings.job?.interval ? 1000
        return API.job.process p
    else
      return false

API.job._iid
API.job.start = (interval=API.settings.job?.interval ? 1000) ->
  future = new Future() # randomise start time so that cluster machines do not all start jobs at exactly the same time
  Meteor.setTimeout (() -> future.return()), Math.floor(Math.random()*interval+1)
  future.wait()
  API.log {msg: 'Starting job runner with interval ' + interval, _cid: process.env.CID, _appid: process.env.APP_ID, function: 'API.job.start', level: 'all'}
  # create a repeating limited stuck check process with id 'STUCK' so that it can check for stuck jobs
  # multiple machines trying to create it won't matter because they will just overwrite each other, eventually only one process will run
  job_limit.remove('*')
  job_process.remove [{group:'STUCK'},{group:'PROGRESS'},{group:'TEST'}]
  job_processing.remove [{group:'STUCK'},{group:'PROGRESS'},{group:'TEST'}]
  job_result.remove [{group:'STUCK'},{group:'PROGRESS'},{group:'TEST'}]
  job_process.insert _id: 'STUCK', repeat: true, function: 'API.job.stuck', priority: 8000, group: 'STUCK', limit: 900000 # 15 mins stuck check
  #job_process.insert _id: 'TEST', repeat: true, function: 'API.test', priority: 8000, group: 'TEST', limit: 86400000 # daily system test
  API.job._iid ?= Meteor.setInterval API.job.next,interval

API.job.start() if not API.job._iid? and API.settings.job?.startup

API.job.running = () -> return API.job._iid? and not job_limit.get('PAUSE')?

API.job.stop = () ->
  # note that processes already processing will keep going, but no new ones will start
  job_limit.insert _id: 'PAUSE'

API.job.stuck = (p) ->
  if p._id is 'STUCK' # the first stuck check after a system restart will have this as ID, so check for hung processes
    if job_processing.find 'NOT _id:STUCK AND NOT _id:TEST AND createdAt:<' + p.createdAt
      API.job.reload(if job_processing.find('NOT _id:STUCK AND NOT _id:TEST AND createdAt:>=' + p.createdAt) then 'createdAt:<' + p.createdAt else '*')
  else if job_processing.count('*') is 0 and job_process.count('*') isnt 0
    API.log {msg:'Job processing seems to be stuck, there are processes waiting but none running', notify:true, level:'WARN'}
  st = API.job.status()
  try
    if p.previous and job_result.get p.previous
      previous = API.job.result p.previous
      if st.jobs.count isnt 0 and previous.jobs.count is st.jobs.count and previous.jobs.oldest?._id is st.jobs.oldest?._id and previous.jobs.newest?._id is st.jobs.newest?._id and previous.jobs.done is st.jobs.done and st.jobs.done isnt st.jobs.count
        # if there are jobs, and previous jobs count matches current, and previous oldest and newest job IDs match current,
        # and amount of jobs done is the same, and amount of jobs done is not all jobs, then something is wrong, send a warning
        API.log {msg:'Job processing seems to be stuck, job amounts have not changed since last check', notify:true, level:'WARN'}
      else if previous.processing.count is st.processing.count and previous.processing.oldest._id is st.processing.oldest._id and previous.processing.newest._id is st.processing.newest._id
        API.log {msg:'Job processing seems to be stuck, processing amounts and oldest and newest have not changed since last check', notify:true, level:'WARN'}
      else if st.jobs.done isnt st.jobs.count and st.processing.count is 0
        API.log {msg:'Job processing seems to be stuck, there are jobs not done but no processes running', notify:true, level:'WARN'}
  # TODO could trigger a reload if it seems processing jobs are just not getting done - can be done en masse or per job not done
  return st

API.job.status = (filter='NOT group:STUCK AND NOT group:PROGRESS AND NOT group:TEST') ->
  res =
    running: API.job.running()
    jobs:
      count: job_job.count('*')
      oldest: {_id: jjo._id, createdAt: jjo.createdAt, created_date: jjo.created_date} if jjo = job_job.find('*', {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jjn._id, createdAt: jjn.createdAt, created_date: jjn.created_date} if jjn = job_job.find('*', true)
      done: job_job.count done:true
    processes:
      count: job_process.count(filter)
      oldest: {_id: jpo._id, createdAt: jpo.createdAt, created_date: jpo.created_date} if jpo = job_process.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jpn._id, createdAt: jpn.createdAt, created_date: jpn.created_date} if jpn = job_process.find(filter, true)
    processing:
      count: job_processing.count(filter)
      oldest: {_id: jpro._id, createdAt: jpro.createdAt, created_date: jpro.created_date} if jpro = job_processing.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jprn._id, createdAt: jprn.createdAt, created_date: jprn.created_date} if jprn = job_processing.find(filter, true)
    results:
      count: job_result.count(filter)
      oldest: {_id: jro._id, createdAt: jro.createdAt, created_date: jro.created_date} if jro = job_result.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jrn._id, createdAt: jrn.createdAt, created_date: jrn.created_date} if jrn = job_result.find(filter, true)
  res.limits = {} # may not be worth reporting on limit index in new structure
  job_limit.each 'NOT last:*', (lm) -> res.limits[lm.group] = {date:lm.created_date,limit:lm.limit}
  return res

API.job.reload = (q='*') ->
  ret = 0
  reloads = []
  if q isnt '*' and job = job_job.get q
    for p in job.processes
      proc = if p._id? then job_processing.get(p._id) else undefined
      if proc?
        ret += 1
        job_processing.remove proc._id
        if not job_result.get(proc._id)? and not job_process.get(proc._id)?
          proc.reloaded ?= []
          proc.reloaded.push proc.createdAt
          reloads.push proc
  else
    job_processing.each q, ((proc) ->
      ret += 1
      if proc.group isnt 'STUCK' and proc.group isnt 'PROGRESS' and not job_result.get(proc._id)? and not job_process.get(proc._id)?
        proc.reloaded ?= []
        proc.reloaded.push proc.createdAt
        reloads.push proc
    )
    job_processing.remove q
  if reloads.length
    job_process.import(reloads)
    job_process.refresh()
  return ret

API.job._progress = (jobid,reload=false) ->
  job = if typeof jobid is 'object' then jobid else job_job.get jobid
  job_result.remove job._id
  total = job.processes.length
  count = 0
  job.processed ?= []
  processed = []
  if job.processed? and job.processed.length is total
    count = job.processed.length
  else
    for i in job.processes
      if job.processed.indexOf(i._id) isnt -1
        count += 1
      else if job_result.get(i._id)?
        count += 1
        processed.push i._id
      else if reload? and not job_processing.get(i._id)? and not job_process.get(i._id)?
        job_process.insert i
  p = count/total * 100
  if p is 100
    job_job.update job._id, {done:true}
    try
      fn = if job.complete.indexOf('API.') is 0 then API else global
      fn = fn[f] for f in job.complete.replace('API.','').split('.')
      fn job
    catch
      if job.group isnt 'JOBTEST'
        text = 'Job ' + (if job.name then job.name else job._id) + ' is complete.'
        email = job.email ? job.user and API.accounts.retrieve(job.user)?.emails[0].address
        API.mail.send to:email, subject:text, text:text
  else if processed.length
    job_job.update job._id, {processed:job.processed.concat(processed)}
  return {createdAt:job.createdAt, progress:p, name:job.name, email:job.email, _id:job._id, new:job.new}

API.job.progress = (jobid,reload=false) ->
  job = if typeof jobid is 'object' then jobid else job_job.get jobid
  if job.new or job.done
    return {createdAt:job.createdAt, progress:(if job.done then 100 else 0), name:job.name, email:job.email, _id:job._id, new:job.new}
  else if job_processing.get job._id
    if checked = job_result.get job._id
      return checked._raw_result['API.job._progress']
    else
      return {createdAt:job.createdAt, progress:0, name:job.name, email:job.email, _id:job._id, new:false}
  else
    API.log msg: 'Checking job progress of ' + job._id, level: 'debug'
    return API.job.process({_id: job._id, priority: 9000, group: 'PROGRESS', limit: 10000, function: 'API.job._progress', args: [job._id,reload]})._raw_result['API.job._progress']

API.job.rerun = (jobid,uid) ->
  job = job_job.get jobid
  job.user = uid if uid
  job.refresh = true
  _id: job_job.insert {new:true, user:job.user}
  Meteor.setTimeout (() -> API.job.create job), 5
  return data: {job:job._id}

API.job.result = (jr,full) ->
  jr = job_result.get(jr) if typeof jr is 'string'
  if full?
    return jr ? {}
  else
    if jr?._raw_result?[jr.function]?
      return jr._raw_result[jr.function]
    else if jr?._raw_result?.string?
      if jr._raw_result.string.indexOf('[') is 0 or jr._raw_result.string.indexOf('{') is 0
        try
          return JSON.parse jr._raw_result.string
      return jr._raw_result.string
    else if jr?._raw_result?.bool?
      return jr._raw_result.bool
    else if jr?._raw_result?.number?
      return jr._raw_result.number
    else if jr?._raw_result?.attachment?
      dc = new Buffer(jr._raw_result.attachment,'base64').toString('utf-8')
      return JSON.parse dc
    else if jr?._raw_result?.error
      return jr._raw_result.error
    else
      return {}

API.job.results = (jobid,full) ->
  results = []
  for ji in job_job.get(jobid)?.processes
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
        result.progress = API.job.progress result.job._id
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

