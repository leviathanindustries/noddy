

import { Random } from 'meteor/random'
import Future from 'fibers/future'
import moment from 'moment'

@job_job = new API.collection index: API.settings.es.index + "_job", type: "job"
@job_process = new API.collection index: API.settings.es.index + "_job", type: "process"
@job_processing = new API.collection index: API.settings.es.index + "_job", type: "processing"
@job_result = new API.collection index: API.settings.es.index + "_job", type: "result"
@job_limit = new API.collection index: API.settings.es.index + "_job", type: "limit"

API.job = {}

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

API.add 'job/:job/progress', get: () -> return if not job = job_job.get(this.urlParams.job) then 404 else API.job.progress job

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
      fnd = 'signature.exact:"' + proc.signature + '" AND NOT exists:"result.error"'
      try
        if typeof job.refresh is 'number' and job.refresh isnt 0
          d = new Date()
          fnd += ' AND createdAt:>' + d.setDate(d.getDate() - job.refresh)
      rs = job_result.find fnd, true
      ofnd = {'signature.exact':proc.signature,save:true}
      rs = job_processing.find(ofnd, true) if not rs?
      ofnd.limit = proc.limit if proc.limit?
      rs = job_process.find(ofnd, true) if not rs? # TODO check undefined limit does not show up as search term
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

API.job.limit = (limitms,fn,args,group) -> # a handy way to directly create a sync throttled process
  pr = {priority:10000,_id:Random.id(),group:(group ? fn), function: fn, args: args, signature: encodeURIComponent(fn + '_' + args), limit: limitms, save: API.settings.dev}
  jp = job_process.insert pr
  jr = job_result.get pr._id
  while not jr?
    future = new Future()
    Meteor.setTimeout (() -> future.return()), limitms
    future.wait()
    jr = job_result.get pr._id
  return jr.result?[fn]

API.job.process = (proc) ->
  proc = job_process.get(proc) if typeof proc isnt 'object'
  return false if typeof proc isnt 'object'
  proc.args = JSON.stringify proc.args if proc.args? and typeof proc.args is 'object' # in case a process is passed directly with non-string args
  try proc._cid = process.env.CID
  try proc._appid = process.env.APP_ID
  proc._id = job_processing.insert proc # in case is a process with no ID, need to catch the ID
  job_process.remove proc._id
  API.log {msg:'Processing ' + proc._id,process:proc,level:'debug',function:'API.job.process'}
  fn = if proc.function.indexOf('API.') is 0 then API else global
  fn = fn[p] for p in proc.function.replace('API.','').split('.')
  try
    proc.result = {}
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
      proc.result[proc.function] = fn.apply this, args
    else
      proc.result[proc.function] = fn args
  catch err
    proc.result = {error: err.toString()}
    API.log msg: 'Job process error', error: err, string: err.toString(), process: proc, level: 'debug'
    if API.settings.log.level in ['debug','all']
      console.log JSON.stringify err
      console.log err.toString()
      console.log proc
  try
    job_result.insert proc # if this fails, we stringify and save that way
  catch
    try
      proc.result.string = JSON.stringify proc.result[proc.function] # try saving as string then change it back
      delete proc.result[proc.function]
      job_result.insert proc
      proc.result[proc.function] = JSON.parse(proc.result.string)
      delete proc.result.string
  job_processing.remove proc._id
  if proc.repeat
    proc.counter ?= 1
    proc.original ?= proc._id
    pn = JSON.parse(JSON.stringify(proc))
    pn.repeat -= 1 if pn.repeat isnt true
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

API.job._ignores = {}
API.job.next = (ignore=[]) ->
  now = Date.now()
  for k, v of API.job._ignores
    if v <= now
      delete API.job._ignores[k]
    else
      ignore.push(k) if k not in ignore
  if job_processing.get 'RELOAD'
    job_processing.remove 'RELOAD'
    API.job.reload()
    # TODO is it worth doing job progress checks here? If so, for all not done jobs?
  else if not job_processing.get('STOP')
    if (API.settings.job?.concurrency ?= 1000000000) <= job_processing.count()
      API.log {msg:'Not running more jobs, job max concurrency reached', _cid: process.env.CID, _appid: process.env.APP_ID, function:'API.job.next'}
    else if (API.settings.job?.memory ? 1300000000) <= process.memoryUsage().rss
      # TODO should check why this is happening, is it memory leak or just legit usage while running lots of jobs?
      # and if legit and being hit on every available machine in the cluster, should trigger alert to start more cluster machines?
      API.log {msg:'Not running more jobs, job max memory reached', _cid: process.env.CID, _appid: process.env.APP_ID, function:'API.job.next'}
    else
      API.log {msg:'Checking for jobs to run',ignore:ignore,function:'API.job.next',level:'all'}
      match = must_not:[{term:{available:false}}] # TODO check this will get matched properly to something where available = false
      match.must_not.push term: 'group.exact':g for g in ignore
      p = job_process.find match, {sort:{priority:{order:'desc'}}, random:true} # TODO check if random sorted wil work - may have to be more complex
      if p and not job_processing.get(p._id)
        if p.limit?
          lm = job_limit.get p.group
          if lm? and lm.last + p.limit > now
            ignore.push p.group
            API.job._ignores[p.group] = now + p.limit
            return API.job.next ignore
          else
            job_limit.insert {group:lm.group,last:lm.last} if lm? and API.settings.dev # keep a history of limit counters until service restarts
            jl = job_limit.insert {_id:p.group,group:p.group,last:now}
            return API.job.process p
        else
          return API.job.process p

API.job._iid
API.job.start = (interval=API.settings.job?.interval ? 1000) ->
  API.log {msg: 'Starting job runner with interval ' + interval, _cid: process.env.CID, _appid: process.env.APP_ID, function: 'API.job.start', level: 'all'}
  # create a repeating limited stuck check process with id 'STUCK' so that it can check for stuck jobs
  # multiple clusters trying to create it wont matter because they will just overwrite each other, eventually only one process will run
  job_limit.remove('*')
  job_process.remove [{function:'API.job.stuck'},{group:'PROGRESS'}]
  job_processing.remove [{function:'API.job.stuck'},{group:'PROGRESS'}]
  job_result.remove [{function:'API.job.stuck'},{group:'PROGRESS'}]
  job_process.insert _id: 'STUCK', repeat: true, function: 'API.job.stuck', priority: 1, group: 'API.job.stuck', limit: 900000
  API.job._iid ?= Meteor.setInterval API.job.next,interval
  job_processing.remove 'STOP'
  if job_processing.count() and not job_processing.get 'RELOAD'
    job_processing.insert _id:'RELOAD', createdAt:Date.now()

API.job.start() if not API.job._iid? and API.settings.job?.startup

API.job.running = () -> return API.job._iid? and not job_processing.get 'STOP'

API.job.stop = () ->
  # note that processes already processing will keep going, but no new ones will start
  if API.job._iid?
      Meteor.clearInterval API.job._iid
      job_processing.insert _id:'STOP', createdAt:Date.now()

API.job.stuck = (p) ->
  job_job.each 'NOT done:true', (rec) -> API.job.progress(rec._id)
  st = API.job.status()
  # compare count, oldest and newest of processes and processing with p.result[function] if it exists
  # if all the same, and if not having timeout after now, send a warning
  # also look for jobs still not done, and if nothing running, consider them stuck
  return st

API.job.status = (filter='*') ->
  res =
    running: API.job.running()
    processes:
      count: job_process.count(filter)
      oldest: {_id: jpo._id, createdAt: jpo.createdAt, created_date: jpo.created_date} if jpo = job_process.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jpn._id, createdAt: jpn.createdAt, created_date: jpn.created_date} if jpn = job_process.find(filter, true)
    processing:
      count: job_processing.count(filter)
      oldest: {_id: jpro._id, createdAt: jpro.createdAt, created_date: jpro.created_date} if jpro = job_processing.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jprn._id, createdAt: jprn.createdAt, created_date: jprn.created_date} if jprn = job_processing.find(filter, true)
    jobs:
      count: job_job.count(filter)
      oldest: {_id: jjo._id, createdAt: jjo.createdAt, created_date: jjo.created_date} if jjo = job_job.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jjn._id, createdAt: jjn.createdAt, created_date: jjn.created_date} if jjn = job_job.find(filter, true)
      done: job_job.count done:true # TODO if allowing a filter in, this will have to take account of possible types of filter query
    results:
      count: job_result.count(filter)
      oldest: {_id: jro._id, createdAt: jro.createdAt, created_date: jro.created_date} if jro = job_result.find(filter, {sort:{createdAt:{order:'asc'}}})
      newest: {_id: jrn._id, createdAt: jrn.createdAt, created_date: jrn.created_date} if jrn = job_result.find(filter, true)
  #groups = API.es.terms 'noddy_job' + (if API.settings.dev then '_dev' else ''), 'job_process,job_processing,job_result', 'group', 1000, true, filter
  res.limits = {}
  return res

API.job.reload = (jobid) ->
  ret = 0
  job_processing.each (if jobid then 'job:'+jobid else '*'), ((proc) ->
    if proc._id not in ['RELOAD','STOP'] and not job_process.get(proc._id) and not job_result.get(proc._id)
      proc.reloaded ?= []
      proc.reloaded.push proc.createdAt
      job_process.insert proc
      ret += 1
    job_processing.remove proc._id
  )
  return ret

API.job._progress = (jobid) ->
  job = if typeof jobid is 'object' then jobid else job_job.get jobid
  job_result.remove job._id
  total = job.processes.length
  count = 0
  for i in job.processes
    count += 1 if job_result.get(i._id)?
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
  return {createdAt:job.createdAt, progress:p, name:job.name, email:job.email, _id:job._id, new:job.new}

API.job.progress = (jobid,limit) ->
  job = if typeof jobid is 'object' then jobid else job_job.get jobid
  if job.new or job.done
    return {createdAt:job.createdAt, progress:(if job.done then 100 else 0), name:job.name, email:job.email, _id:job._id, new:job.new}
  else if job_processing.get job._id
    if checked = job_result.get job._id
      return checked.result['API.job._progress']
    else
      return {createdAt:job.createdAt, progress:0, name:job.name, email:job.email, _id:job._id, new:false}
  else
    API.log msg: 'Checking job progress of ' + job._id, level: 'debug'
    return API.job.process({_id: job._id, group: 'PROGRESS', limit: limit ? 5000, function: 'API.job._progress', args: job._id}).result['API.job._progress']

API.job.rerun = (jobid,uid) ->
  job = job_job.get jobid
  job.user = uid if uid
  job.refresh = true
  _id: job_job.insert {new:true, user:job.user}
  Meteor.setTimeout (() -> API.job.create job), 5
  return data: {job:job._id}

API.job.results = (jobid,full) ->
  results = []
  for ji in job_job.get(jobid)?.processes
    jr = job_result.get(ji._id) ? {}
    if full?
      results.push jr
    else
      res = if jr?.result?.string? and not jr?.result?[jr.function]? then JSON.parse(jr.result.string) else jr.result[jr.function]
      res ?= {}
      results.push res
  return results
