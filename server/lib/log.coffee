
import { Random } from 'meteor/random'
import moment from 'moment'
import Future from 'fibers/future'


_log_today = moment(Date.now(), "x").format "YYYYMMDD"
_log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today
_log_last = Date.now()
_ls = {a:[],b:[]}
_lsp = "a"
_log_stack = _ls[_lsp]
_log_flush = () ->
  _log_last = Date.now()
  if _lsp is "a"
    _log_stack = _ls.b
    _lsp = "b"
  else
    _log_stack = _ls.a
    _lsp = "a"
  console.log('Switched log stack to ' + _lsp) if API.settings.dev
  Meteor.setTimeout (() ->
    _wl = if _lsp is "a" then "b" else "a"
    imported = _log_index.import _ls[_wl]
    _ls[_wl] = []
    if API.settings.dev
      console.log 'Flushed logs from stack ' + _wl
      #console.log imported
      console.log 'Log stack lengths now a:' + _ls.a.length + ' b:' + _ls.b.length
  ), 5


# although the log endpoint is close to what a mounted collection endpoint intends to be, 
# and although collection mounting allows customising actions and auth, the log is sufficiently 
# different, and is core to functionality, that it is expressly defined here instead of being a mount
_log_query = (params,day='',user) ->
  day = '/' + _log_today if day is 'today'
  day = '/' +moment(Date.now(), "x").subtract(1,'days').format("YYYYMMDD") if day is 'yesterday'
  day = '/' + day if day.length and day.indexOf('/') isnt 0
  q = API.collection._translate params
  q.sort = {'createdAt': {order: 'desc'}} if typeof q is 'object' and not q.sort?
  res = API.es.call 'POST', API.settings.es.index + '_log' + day + '/_search', q
  res ?= {}
  if res?.hits?.hits? and not user? and not API.settings.dev # which users are allowed to see full logs, if any? and what can others see?
    for h of res.hits.hits
      clean = {}
      fl = if res.hits.hits[h]._source? then '_source' else 'fields'
      for k of res.hits.hits[h][fl]
         if k in ['endpoint','function','level','createdAt','created_date','_id','_ip']
           clean[k] = res.hits.hits[h][fl][k]
      res.hits.hits[h][fl] = clean
  # what terms and aggs can certain users see? if any?
  res.q = q if API.settings.dev
  return res
  
API.add 'log',
  get:
    authOptional: true
    action: () -> return _log_query this.queryParams, undefined, this.user
  post:
    authOptional: true
    action: () -> return _log_query this.request.body, undefined, this.user
API.add 'log/:yyyymmdd',
  get:
    authOptional: true
    action: () -> return _log_query this.queryParams, this.urlParams.yyyymmdd, this.user
  post:
    authOptional: true
    action: () -> return _log_query this.request.body, this.urlParams.yyyymmdd, this.user

API.add 'log/days', get: () -> return API.log.days()

API.add 'log/stack',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        return API.log.stack this.queryParams
      else
        return {status: 'error', info: 'Log stack is not in use'}

API.add 'log/stack/local',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        return API.log.local this.queryParams
      else
        return {status: 'error', info: 'Log stack is not in use'}

API.add 'log/stack/length',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        return {current: _lsp, a: _ls.a.length, b: _ls.b.length, last: moment(_log_last, "x").format("YYYY-MM-DD HHmm.ss")}
      else
        return {info: 'Log stack is not in use'}

API.add 'log/stack/flush',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        _alt = if _lsp is "a" then "b" else "a"
        ret = { from: { stack:_lsp, a:_ls.a.length, b:_ls.b.length } }
        _log_flush()
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 5000
        future.wait()
        ret.to = {stack:_lsp, a:_ls.a.length, b:_ls.b.length }
        return true
      else
        return {info: 'Log stack is not in use'}

API.add 'log/:yyyymmdd/clear',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      if this.urlParams.yyyymmdd is 'today' or this.urlParams.yyyymmdd is _log_today
        _ls.a = []
        _ls.b = []
        _log_index.remove '*'
      else if this.urlParams.yyyymmdd is '_all'
        _ls.a = []
        _ls.b = []
        API.es.call 'DELETE', API.settings.es.index + '_log'
        _log_today = moment(Date.now(), "x").format "YYYYMMDD"
        _log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today
      else if this.urlParams.yyyymmdd.indexOf('-') isnt -1
        p = this.urlParams.yyyymmdd.split '-'
        s = moment p[0]
        while p[1] isnt sf = s.format "YYYYMMDD"
          console.log sf
          API.es.call 'DELETE', API.settings.es.index + '_log/' + s.format "YYYYMMDD"
          s.add 1,'days'
        console.log p[1]
        API.es.call 'DELETE', API.settings.es.index + '_log/' + p[1]
      else
        API.es.call 'DELETE', API.settings.es.index + '_log/' + this.urlParams.yyyymmdd
      return true

API.add 'log/:yyyymmdd/count', get: () -> return API.es.count API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd), '', API.collection._translate(this.queryParams)

API.add 'log/:yyyymmdd/keys', get: () -> return API.es.keys API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd)

API.add 'log/:yyyymmdd/:key/count', get: () -> return API.es.count API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd), this.urlParams.key, API.collection._translate(this.queryParams)

API.add 'log/:yyyymmdd/:key/min', get: () -> return API.es.min API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd), this.queryParams.key, API.collection._translate(this.queryParams)

API.add 'log/:yyyymmdd/:key/max', get: () -> return API.es.max API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd), this.queryParams.key, API.collection._translate(this.queryParams)

API.add 'log/:yyyymmdd/:key/range', get: () -> return API.es.range API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd), this.queryParams.key, API.collection._translate(this.queryParams)

API.add 'log/:yyyymmdd/:key/terms', get: () -> return API.es.terms API.settings.es.index + '_log', (if this.urlParams.yyyymmdd is 'today' then _log_today else if this.urlParams.yyyymmdd is '_all' then '' else this.urlParams.yyyymmdd), this.urlParams.key, API.collection._translate(this.queryParams), this.queryParams.size, this.queryParams.counts



API.log = (opts, fn, lvl='debug') ->
  # TODO use a combo of this and the structure system to find a function name
  # e.g. if structure system stores a checksum of the function, then this could find the function name from that
  # so that the log object function value can be added if not provided, to know which function called for this log
  try
    opts = { msg: opts } if typeof opts is 'string'
    opts.function ?= fn
    if not opts.function and typeof API.log.caller is 'function'
      try
        cs = API.log.caller.toString().toLowerCase()
        cslog = cs.split('api.log')[1].split(')')[0].split('+')[0].split('#')[0]
        csargs = cs.split('(')[1].split(')')[0]
        ffn = API.structure.logarg2fn (cslog + csargs).replace(/[^a-z0-9]/g,'')
        opts.function = ffn if typeof ffn is 'string' and ffn.startsWith('API.')
    if opts.function? and not opts.group?
      try opts.group = if opts.function.indexOf('service') isnt -1 then opts.function.split('service.')[1].split('.')[0] else if opts.function.indexOf('use') isnt -1 then opts.function.split('use.')[1].split('.')[0] else opts.function.replace('API.','').split('.')[0]
    opts.level ?= opts.lvl
    delete opts.lvl
    opts.level ?= lvl
    opts.createdAt = Date.now()
    opts.created_date = moment(opts.createdAt, "x").format "YYYY-MM-DD HHmm.ss"

    loglevels = ['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'off']
    loglevel = API.settings.log?.level ? 'all';
    if loglevels.indexOf(loglevel) <= loglevels.indexOf opts.level
      if opts.notify and API.settings.log?.notify
        try
          os = JSON.parse(JSON.stringify(opts))
        catch
          os = opts
        Meteor.setTimeout (() -> API.notify os), 100

      today = moment(opts.createdAt, "x").format "YYYYMMDD"
      if today isnt _log_today
        if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
          _log_flush()
          future = new Future()
          Meteor.setTimeout (() -> future.return()), 10
          future.wait()
        _log_today = today
        _log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today

      for o of opts
        if not opts[o]?
          delete opts[o]
        else if typeof opts[o] isnt 'string'
          try
            opts[o] = JSON.stringify opts[o]
          catch
            try
              opts[o] = opts[o].toString()
            catch
              delete opts[o]

      try opts._ip = API.status.ip() #this would not be possible right at start up

      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        API.settings.log.bulk ?= 5000
        API.settings.log.timeout ?= 1800000
        opts._id = Random.id()
        _log_stack.unshift opts
        if _log_stack.length >= API.settings.log.bulk or Date.now() - _log_last > API.settings.log.timeout or opts.flush?
          _log_flush()
      else
        _log_index.insert opts

      if loglevels.indexOf(loglevel) <= loglevels.indexOf 'debug'
        console.log opts.msg.toUpperCase() if opts.msg
        console.log JSON.stringify(opts), '\n'

  catch err
    console.log 'API LOG ERROR\n', opts, '\n', fn, '\n', lvl, '\n', err

API.log.days = () ->
  days = []
  mapping = API.es.call 'GET', API.settings.es.index + '_log/_mapping'
  for m of mapping
    if mapping[m].mappings?
      for t of mapping[m].mappings
        days.push t
  return days

API.logstack = (key,val) ->
  if not key? and not val?
    return _log_stack
  else
    logs = []
    if key?
      if val?
        for ln in _log_stack
          logs.push(ln) if ln[key]? and ln[key] is val
      else
        for ln in _log_stack
          logs.push(ln) if ln[key]?
    else if val
      for ln in _log_stack
        if val in JSON.stringify ln
          logs.push ln
    return logs

API.log.local = () ->
  ld = API.log.days()
  return
    cluster: 1 + (if API.settings.cluster?.ip? then API.settings.cluster.ip.length else 0)
    oldest: ld[0]
    latest: ld.pop()
    length: _log_stack.length
    last: moment(_log_last, "x").format("YYYY-MM-DD HHmm.ss")
    bulk: API.settings.log.bulk
    timeout: API.settings.log.timeout
    current: _lsp
    a: _ls.a
    b: _ls.b
  
API.log.stack = (params={}) ->
  res = _.clone _log_stack
  for ip in API.settings.cluster?.ip ? []
    try
      lu = if ip.indexOf('://') is -1 then 'http://' + ip else ip 
      if lu.indexOf('log/stack') is -1
        if lu.indexOf(':3') is -1
          lu += ':' + if API.settings.dev then '3002' else '3333'
        lu += '/api/log/stack/local'
      rml = HTTP.call('GET', lu).data
      res = res.concat rml[rml.current]
  res = res.sort (a,b) -> return if a.createdAt > b.createdAt then -1 else 1
  params.from ?= 0
  if params.q?
    rq = []
    k = false
    v = params.q
    if params.q.indexOf(':') isnt -1
      parts = params.q.split(':')
      k = parts[0]
      v = parts[1]
    vn = false
    if v.indexOf('NOT ') isnt -1
      vn = true
      v = v.replace(' NOT ','').replace('NOT ','')
    v = v.toLowerCase().replace(/"/g,'')
    for r in res # could improve this to handle AND OR NOT etc, or complex query objects, but this should do for now
      break if params.size and rq.length >= (params.size + params.from)
      if vn
        rq.push(r) if (k isnt false and r[k]? and r[k].toLowerCase().indexOf(v) is -1) or (k is false and JSON.stringify(r).toLowerCase().indexOf(v) is -1)
      else
        rq.push(r) if (k isnt false and r[k]? and r[k].toLowerCase().indexOf(v) isnt -1) or JSON.stringify(r).toLowerCase().indexOf(v) isnt -1
    res = rq
  res = res.slice(params.from) if params.from and res.length > params.from
  res = res.slice(0,params.size) if params.size and res.length > params.size
  return res
    

API.notify = (opts) ->
  try
    note = opts.notify
    if note is true
      note = {}
    else if typeof note is 'string'
      if note.indexOf '@' isnt -1
        note = to: note
      # TODO otherwise should already be a dot notation string to an api setting or object

    if typeof note is 'object'
      note.text ?= note.msg ? opts.msg
      note.subject ?= API.settings.name ? 'API log message'
      note.from ?= API.settings.log?.from ? 'alert@cottagelabs.com'
      note.to ?= API.settings.log?.to ? 'mark@cottagelabs.com'
      API.mail.send note

  catch err
    console.log 'API LOG NOTIFICATION ERROR\n', err

