
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
      console.log imported
      console.log 'Log stack lengths now a:' + _ls.a.length + ' b:' + _ls.b.length
  ), 5



API.add 'log',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      return _log_index.search this.queryParams

API.add 'log/stack',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        return {length: _log_stack.length, last: moment(_log_last, "x").format("YYYY-MM-DD HHmm.ss"), bulk: API.settings.log.bulk, timeout: API.settings.log.timeout, current: _lsp, a: _ls.a, b: _ls.b}
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

API.add 'log/clear',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      _ls.a = []
      _ls.b = []
      _log_index.remove '*'
      return true

API.add 'log/clear/_all',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      _ls.a = []
      _ls.b = []
      API.es.call 'DELETE', API.settings.es.index + '_log'
      _log_today = moment(Date.now(), "x").format "YYYYMMDD"
      _log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today
      return true


API.log = (opts, fn, lvl='debug') ->
  try
    opts = { msg: opts } if typeof opts is 'string'
    opts.function ?= fn
    opts.level ?= opts.lvl
    delete opts.lvl
    opts.level ?= lvl
    opts.createdAt = Date.now()
    opts.created_date = moment(opts.createdAt, "x").format "YYYY-MM-DD HHmm.ss"
    # TODO try to set some opts vars for which server the error is running on...

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

      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        API.settings.log.bulk = 5000 if API.settings.log.bulk is undefined
        API.settings.log.timeout ?= 300000
        opts._id = Random.id()
        _log_stack.unshift opts
        if _log_stack.length >= API.settings.log.bulk or Date.now() - _log_last > API.settings.log.timeout
          _log_flush()
      else
        _log_index.insert opts

      if loglevels.indexOf(loglevel) <= loglevels.indexOf 'debug'
        console.log opts.msg.toUpperCase() if opts.msg
        console.log JSON.stringify(opts), '\n'

  catch err
    console.log 'API LOG ERROR\n', opts, '\n', fn, '\n', lvl, '\n', err

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

