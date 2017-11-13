import moment from 'moment'

_log_today = moment(Date.now(), "x").format "YYYYMMDD"
_log_index = new API.collection index: API.settings.es.index + '_log', type: _log_today

API.log = (opts, fn, lvl='debug') ->
  try
    opts = { msg: opts } if typeof opts is 'string'
    opts.function ?= fn
    opts.level ?= lvl
    opts.createdAt = Date.now()
    opts.created_date = moment(opts.createdAt, "x").format "YYYY-MM-DD HHmm"
    # TODO try to set some opts vars for which server the error is running on...

    loglevels = ['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'off']
    loglevel = API.settings.log?.level ? 'all';
    if loglevels.indexOf(loglevel) <= loglevels.indexOf opts.level
      Meteor.setTimeout (-> API.notify opts), 100 if opts.notify and API.settings.log.notify

      today = moment(opts.createdAt, "x").format "YYYYMMDD"
      if today isnt _log_today
        _log_today = today;
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

    if typeof note is 'object' and JSON.stringify note isnt '{}'
      note.msg ?= opts.msg
      note.text ?= opts.text
      note.subject ?= API.settings.name ? 'API log message'
      note.from ?= API.settings.log.from ? 'alert@cottagelabs.com'
      note.to ?= API.settings.log.to ? 'mark@cottagelabs.com'
      API.mail.send note

  catch err
    console.log 'API LOG NOTIFICATION ERROR\n', err

