

import moment from 'moment'

_log_today = moment(Date.now(), "x").format "YYYYMMDD"
_log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today
_log_stack = []
_log_last = Date.now()

API.add 'log',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      return _log_index.search this.queryParams

API.add 'log/stack',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      return {length: _log_stack.length, last: _log_last, stack: _log_stack}

API.add 'log/stack/flush',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      ln = _log_stack.length
      logged = _log_index.import _log_stack
      _log_stack = []
      _log_last = Date.now()
      return ln

API.add 'log/clear',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      _log_index.remove '*'
      return true

API.add 'log/clear/_all',
  get:
    authRequired: if API.settings.dev then undefined else 'root'
    action: () ->
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
      if opts.notify and API.settings.log.notify
        Meteor.setTimeout (() -> API.notify opts), 100

      today = moment(opts.createdAt, "x").format "YYYYMMDD"
      if today isnt _log_today
        _log_today = today
        _log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today

      for o of opts
        if not opts[o]?
          delete opts[o]
        else if typeof opts[o] isnt 'string'
          if o is 'error' and typeof opts[o] is 'object'
            try
              opts[o] = opts[o].toString()
            catch
              opts[o] = JSON.stringify opts[o]
          opts[o] = JSON.stringify opts[o]

      if API.settings.log?.bulk isnt 0 and API.settings.log?.bulk isnt false
        API.settings.log.bulk = 5000 if API.settings.log.bulk is undefined
        API.settings.log.timeout ?= 300000
        _log_stack.push opts
        if _log_stack.length >= API.settings.log.bulk or Date.now() - _log_last > API.settings.log.timeout
          logged = _log_index.import _log_stack
          _log_stack = []
          _log_last = Date.now()
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
      note.msg ?= opts.msg
      note.text ?= opts.text
      note.subject ?= API.settings.name ? 'API log message'
      note.from ?= API.settings.log.from ? 'alert@cottagelabs.com'
      note.to ?= API.settings.log.to ? 'mark@cottagelabs.com'
      API.mail.send note

  catch err
    console.log 'API LOG NOTIFICATION ERROR\n', err

