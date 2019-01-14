

import moment from 'moment'
import { Random } from 'meteor/random'

# worth extending mongo.collection, or just not use it?
# https://stackoverflow.com/questions/34979661/extending-mongo-collection-breaks-find-method
# decided not to use it. If Mongo is desired in future, this collection object can be used to extend and wrap it

# there are a few direct debug console.log calls in here, depending on whether or not the collection is
# one with _log in the name or not, just to avoid endless log loops but still have useful output in debug mode for dev

API.collection = (opts, dev=API.settings.dev) ->
  opts = { type: opts } if typeof opts is 'string'
  opts.index ?= API.settings.es.index
  this._index = opts.index
  this._type = opts.type
  this._route = '/' + this._index
  this._route += '/' + this._type if this._type
  this._mapping = opts.mapping
  API.es.map this._index, this._type, this._mapping, undefined, dev # only has effect if no mapping already
  this._history = opts.history if this._route.indexOf('_log') is -1
  API.es.map(this._index, this._type + '_history', this._mapping, undefined, dev) if this._history
  #this._replicate = opts.replicate; # does nothing yet, but could replicate all creates/updates/deletes to alternate cluster address
  this._mount = opts.mount?
  this.mount(if typeof opts.mount is 'object' then opts.mount else undefined) if this._mount
  if opts.backup
    try
      API.backup.register this._index, this._type
      this._backup = true

API.collection.prototype.map = (mapping, dev=API.settings.dev) ->
  this._mapping = mapping
  return API.es.map this._index, this._type, mapping, true, dev # would overwrite any existing mapping
API.collection.prototype.mapping = (original, dev=API.settings.dev) -> return if this._mapping and original then this._mapping else API.es.mapping this._index, this._type, dev

API.collection.prototype.refresh = (dev=API.settings.dev) -> API.es.refresh this._index, dev

API.collection.prototype.delete = (confirm, history, dev=API.settings.dev) ->
  # TODO who should be allowed to do this, and how should it be recorded in history, if history is not itself removed?
  this.remove('*') if confirm is '*'
  API.es.call('DELETE', this._route, undefined, undefined, undefined, undefined, undefined, undefined, dev) if confirm is true
  API.es.call('DELETE', this._route + '_history', undefined, undefined, undefined, undefined, undefined, undefined, dev) if confirm is true and history is true and this._history
  return true

API.collection.prototype.history = (action, doc, uid, dev=API.settings.dev) ->
  # NOTE even if a collection has history turned on, the uid of the user who made the
  # change will not be known unless the code calling the insert, delete etc functions includes it
  # TODO is it worth having a collection setting that makes this required? But then what about cases where it may not actually be needed?
  if (action is undefined) or action not in ['insert', 'update', 'remove']
    # TODO action could actually be a usual search q / doc id here, so would need to check if it meets the criteria
    # and if action was a doc id, doc could be a search q
    # and history search should probably have a default descending sort applied to it
    q = API.collection._translate(action ?= '*', doc)
    if typeof q is 'string'
      return API.es.call 'GET', this._route + '_history/_search?' + (if q.indexOf('?') is 0 then q.replace('?', '') else q), undefined, undefined, undefined, undefined, undefined, dev
    else
      return API.es.call 'POST', this._route + '_history/_search', q, undefined, undefined, undefined, undefined, undefined, dev
  else
    record = true
    try
      delete doc.retrievedAt
      delete doc.retrieved_date
      record = false if _.isEmpty doc
    # NOTE the bulk method below also does its own history writing if bulk changes are made to a collection with history enabled
    if record
      change =
        action: action
        document: if typeof doc is 'object' then doc._id else doc
        createdAt: Date.now()
        uid: uid
      change.created_date = moment(change.createdAt, "x").format "YYYY-MM-DD HHmm.ss"
      change[action] = doc if action isnt 'remove'
      ret = API.es.call 'POST', this._route + '_history', change, undefined, undefined, undefined, undefined, undefined, dev
      if not ret?
        if change[action]?
          change.string = JSON.stringify change[action]
          delete change[action]
          ret = API.es.call 'POST', this._route + '_history', change, undefined, undefined, undefined, undefined, undefined, dev
        if not ret?
          API.log msg:'History logging failing',error:err,action:action,doc:doc,uid:uid

API.collection.prototype.fetch_history = (q, opts={}, dev=API.settings.dev) ->
  qy = API.collection._translate q, opts
  qy.from ?= 0
  qy.size ?= 3000
  results = []
  res = API.es.call 'POST', this._route + '_history/_search', qy, undefined, undefined, true, undefined, undefined, dev
  if res.hits.hits.length
    for h in res.hits.hits
      results.push h._source ? h.fields ? {_id: h._id}
  return results if not res?._scroll_id?
  res = API.es.call 'GET', '/_search/scroll', undefined, undefined, undefined, res._scroll_id, undefined, undefined, dev
  return results if not res?._scroll_id? or not res.hits?.hits? or res.hits.hits.length is 0
  while (res.hits.hits.length)
    for h in res.hits.hits
      hr = h._source ? h.fields ? {_id: h._id}
      hr[hr.action] = JSON.parse(hr.string) if hr.string? and hr.action?
      results.push hr
    res = API.es.call 'GET', '/_search/scroll', undefined, undefined, undefined, res._scroll_id, undefined, undefined, dev
  this.refresh(dev)
  return results

# TODO add rewind and replay functions that can work through history records and apply / remove them in order to / from a given record, and allow to specify the date range to play
# and as it is a doc with history, would need to record the last state of the doc change, and record that as a rewind / replay history event

API.collection.prototype.get = (rid, versioned, dev=API.settings.dev) ->
  # TODO is there any case for recording who has accessed certain documents?
  if typeof rid is 'number' or (typeof rid is 'string' and rid.indexOf(' ') is -1 and rid.indexOf(':') is -1 and rid.indexOf('/') is -1 and rid.indexOf('*') is -1)
    check = API.es.call 'GET', this._route + '/' + rid, undefined, undefined, undefined, undefined, undefined, undefined, dev
    return (if versioned then check else check._source) if check?.found isnt false and check?.status isnt 'error' and check?.statusCode isnt 404 and check?._source?
  return undefined

API.collection.prototype.insert = (q, obj, uid, refresh, dev=API.settings.dev) ->
  if typeof q is 'string' and typeof obj is 'object'
    obj._id = q
  else if typeof q is 'object' and not obj?
    obj = q
  if Array.isArray obj
    for o of obj
      obj[o].createdAt = Date.now()
      obj[o].created_date = moment(obj[o].createdAt, "x").format "YYYY-MM-DD HHmm.ss"
      obj[o]._id ?= Random.id()
    return this.bulk obj, 'index', uid, undefined, dev
  else
    obj.createdAt = Date.now()
    obj.created_date = moment(obj.createdAt, "x").format "YYYY-MM-DD HHmm.ss"
    obj._id ?= Random.id()
    this.history('insert', obj, uid, dev) if this._history
    return API.es.call('POST', this._route + '/' + obj._id, obj, refresh, undefined, undefined, undefined, undefined, dev)?._id

API.collection.prototype.update = (q, obj, uid, refresh, versioned, partial, dev=API.settings.dev) ->
  # versioned here can be a version number, in which case the update will only work if it can update onto that version, otherwise returns 409
  # if no version number provided, versioning of the update will still be used for internal clash avoidance
  # and will not necessarily be versioned to the version the user last saw - just to the last version this update method retrieved immediately before the action.
  # TODO? to delete an already set value, the update obj should use the value '$DELETE' for the key to delete
  return undefined if obj?.script? and partial isnt true
  q ?= obj._id
  return false if not q?
  res = this.get q, true, dev
  if res
    rec = res._source
    if _.keys(obj).length is 1 and typeof _.values(obj)[0] is 'string' and  (_.values(obj)[0].indexOf('+') is 0 or _.values(obj)[0].indexOf('-') is 0)
      if rec[_.keys(obj)[0]]? and typeof rec[_.keys(obj)[0]] is 'number'
        partial = true
        obj = {script: "ctx._source." + _.keys(obj)[0] + _.values(obj)[0].replace('+=','+').replace('-=','-').replace('+','+=').replace('-','-=')}
      else
        obj[_.keys(obj)[0]] = 1
    if not partial
      for k of obj
        API.collection._dot(rec,k,obj[k]) if k isnt '_id'
      rec.updatedAt = Date.now()
      rec.updated_date = moment(rec.updatedAt, "x").format "YYYY-MM-DD HHmm.ss"
    API.log({ msg: 'Updating ' + this._route + '/' + rec._id, qry: q, refresh: refresh, versioned: versioned, partial: partial, level: 'debug' }) if this._route.indexOf('_log') is -1
    rs = API.es.call 'POST', this._route + '/' + rec._id, (if partial then obj else rec), refresh, versioned, undefined, undefined, partial, dev
    if rs is 409
      # TODO think about whether using versioned updates is useful all the time or not. For now, it will only be used if version is set by whatever 
      return 409
    else
      if this._history
        obj._id = rec._id
        this.history 'update', (if partial then obj else rec), uid
      return if rs?._version? then rs._version else rs
  else
    # TODO alter this to return something and set action to 'update' to get a bulk each instead of individual record updates
    return this.each q, undefined, ((res) -> this.update res._id, obj, uid, refresh, versioned, partial, dev), undefined, uid, undefined, dev

API.collection.prototype.remove = (q, uid, dev=API.settings.dev) ->
  if (typeof q is 'string' or typeof q is 'number') and this.get q
    this.history('remove', q, uid, dev) if this._history
    API.es.call 'DELETE', this._route + '/' + q, undefined, undefined, undefined, undefined, undefined, undefined, dev
    return true
  else if q is '*'
    # TODO who should be allowed to do this, and how should the event be record in the history?
    omp = this.mapping true, dev
    API.es.call 'DELETE', this._route, undefined, undefined, undefined, undefined, undefined, undefined, dev
    API.es.map this._index, this._type, omp, undefined, dev
    return true
  else
    # TODO alter this to return the record ID and set action to 'remove' to get a bulk each instead of individual record removes
    return this.each q, undefined, ((res) -> this.remove res._id, uid, dev), undefined, uid, undefined, dev

API.collection.prototype.search = (q, opts, versioned, dev=API.settings.dev) ->
  # NOTE is there any case for recording who has done searches? - a write for every search could be a heavy load...
  # or should it be possible to apply certain restrictions on what the search returns?
  # Perhaps - but then this coud/should be applied by the service providing access to the collection
  try
    versioned = opts.versioned
    delete opts.versioned
  if opts is 'versioned'
    versioned = true
    opts = undefined
  q = API.collection._translate q, opts
  if not q?
    return undefined
  else if typeof q is 'string'
    res = API.es.call 'GET', this._route + '/_search?' + (if versioned then 'version=true&' else '') + (if q.indexOf('?') is 0 then q.replace('?', '') else q), undefined, undefined, undefined, undefined, undefined, undefined, dev
    res.q = q if API.settings.dev
    return res
  else
    res = API.es.call 'POST', this._route + '/_search' + (if versioned then '?version=true' else ''), q, undefined, undefined, undefined, undefined, undefined, dev
    res.q = q if API.settings.dev
    return res

API.collection.prototype.find = (q, opts, versioned, dev=API.settings.dev) ->
  try versioned = opts.versioned
  versioned = true if opts is 'versioned'
  got = this.get q, versioned, dev
  if got?
    return got
  else
    try
      hits = this.search(q, opts, versioned, dev).hits.hits
      return if hits.length isnt 0 then (if versioned then hits[0] else hits[0]._source ? hits[0].fields ? {_id: hits[0]._id}) else undefined
    catch err
      API.log({ msg: 'Collection find threw error', q: q, level: 'error', error: err }) if this._route.indexOf('_log') is -1
      return undefined

API.collection.prototype.import = (recs, uid, dev=API.settings.dev) ->
  return this.bulk recs, 'index', uid, undefined, dev

API.collection.prototype.bulk = (recs, action, uid, bulk, dev=API.settings.dev) ->
  # ES uses index/update/delete whereas I've used insert/update/remove in collections, so accept either her them
  # ES accepts create too, which will only create if not already existing whereas index overwrites - but difference not needed yet
  return false if not action? or not recs? or recs.length < 1 or typeof recs isnt 'object' or ['insert','index','update','remove','delete'].indexOf(action) is -1
  # recs must be a list of records, or change docs, or ID strings
  # NOTE what about versioning and version clashes
  # is it worth the bulk process "locking" other collection writes while it runs? How would that work across a cluster? Would need a lock index...
  # it may be better for update and remove to just behave in this way anyway, depends what actions have to occur on those records
  # NOTE that for bulk update this so far only works with docs. Also, docs don't work on dot notation - to replace a value in an object, whole object must be specified
  ret = API.es.bulk this._index, this._type, recs, (if action is 'insert' then 'index' else if action is 'remove' then 'delete' else action), bulk, dev
  if ret? # what is the best check here?
    if this._history
      histories = []
      for rec in recs
        change =
          action: if action is 'index' then 'insert' else if action is 'delete' then 'remove' else action
          bulk: true
          document: if typeof rec is 'object' then rec._id else rec
          createdAt: Date.now()
          uid: uid
          string: JSON.stringify rec
        change.created_date = moment(change.createdAt, "x").format "YYYY-MM-DD HHmm.ss"
        histories.push change
      historied = API.es.bulk this._index, this._type + '_history', histories, undefined, undefined, dev
      if not historied?
        API.log msg:'Bulk history logging failing',error:err,action:action,doc:doc,uid:uid
    return ret
  else
    return false

API.collection.prototype.each = (q, opts, fn, action, uid, scroll, dev=API.settings.dev) ->
  # each executes the function for each record. If the function makes changes to a record and saves those changes, 
  # this can cause many writes to the collection. So, instead, that sort of function could return something
  # and if the action has also been specified then all the returned values will be used to do a bulk write to the collection index.
  # suitable returns would be entire records for insert, record update objects for update, or record IDs for remove
  # this does not allow different actions for different records that are operated on - so has to be bulks of the same action
  if fn is undefined and typeof opts is 'function'
    fn = opts
    opts = undefined
  opts ?= {}
  qy = API.collection._translate q, opts
  qy.from ?= 0
  qy.size ?= if scroll then 250 else 500
  res = API.es.call 'POST', this._route + '/_search', qy, undefined, undefined, true, undefined, undefined, dev
  return 0 if not res?._scroll_id?
  scrollids = []
  scrollids.push(res._scroll_id) if scroll?
  res = API.es.call 'GET', '/_search/scroll', undefined, undefined, undefined, res._scroll_id, scroll, undefined, dev
  return 0 if not res?._scroll_id? or not res.hits?.hits? or res.hits.hits.length is 0
  total = res.hits.total
  processed = 0
  updates = []
  while (res.hits.hits.length)
    scrollids.push(res._scroll_id) if scroll?
    processed += res.hits.hits.length
    for h in res.hits.hits
      fn = fn.bind this
      fr = fn h._source ? h.fields ? {_id: h._id}
      updates.push(fr) if fr? and (typeof fr is 'object' or typeof fr is 'string')
    res = API.es.call 'GET', '/_search/scroll', undefined, undefined, undefined, res._scroll_id, scroll, undefined, dev
  for sid in scrollids
    try API.es.call 'DELETE', '_search/scroll', undefined, undefined, undefined, sid, undefined, undefined, dev
  if action? and updates.length
    this.bulk updates, action, uid, undefined, dev
  this.refresh(dev)
  return if action then {total: total, updated:updates.length, processed:processed} else processed

API.collection.prototype.fetch = (q, opts={}, dev=API.settings.dev) ->
  qy = API.collection._translate q, opts
  qy.from ?= 0
  qy.size ?= 3000
  results = []
  res = API.es.call 'POST', this._route + '/_search', qy, undefined, undefined, true, undefined, undefined, dev
  if res.hits.hits.length
    for h in res.hits.hits
      results.push h._source ? h.fields ? {_id: h._id}
    # scroll queries that are not of scan type will have results in the first request, whereas scan queries will not
  return results if not res?._scroll_id?
  res = API.es.call 'GET', '/_search/scroll', undefined, undefined, undefined, res._scroll_id, undefined, undefined, dev
  return results if not res?._scroll_id? or not res.hits?.hits? or res.hits.hits.length is 0
  while (res.hits.hits.length)
    for h in res.hits.hits
      results.push h._source ? h.fields ? {_id: h._id}
    res = API.es.call 'GET', '/_search/scroll', undefined, undefined, undefined, res._scroll_id, undefined, undefined, dev
  this.refresh(dev)
  return results

API.collection.prototype.count = (key, q, dev=API.settings.dev) ->
  return API.es.count this._index, this._type, key, API.collection._translate(q), dev

API.collection.prototype.min = (key, q, dev=API.settings.dev) ->
  return API.es.min this._index, this._type, key, API.collection._translate(q), dev

API.collection.prototype.max = (key, q, dev=API.settings.dev) ->
  return API.es.max this._index, this._type, key, API.collection._translate(q), dev

API.collection.prototype.range = (key, q, dev=API.settings.dev) ->
  return API.es.range this._index, this._type, key, API.collection._translate(q), dev

API.collection.prototype.terms = (key, q, size=100, counts=false, dev=API.settings.dev) ->
  key = key.replace('.exact','')+'.exact' if true # TODO should check the mapping to see if .exact is relevant for key, and have a way for user to decide
  return API.es.terms this._index, this._type, key, API.collection._translate(q), size, counts, dev

API.collection.prototype.keys = (dev=API.settings.dev) ->
  return API.es.keys this._index, this._type, dev

API.collection.prototype.job = (q, fn, complete) ->
  # TODO for a given query set, create a job that does some fn to all of them
  # when the job has finished all the processes, it should run the complete fn, if it is set
  return false

API.collection.prototype.mount = (opts={}) ->
  # TODO add terms endpoint to mount as well, so that keys can be output as autocomplete lists
  # will need opts to control which keys are allowed, and auth controls for them. May also want this but nothing else to be mounted
  opts.route ?= this._index + '/' + this._type
  opts.search ?= true
  opts.secure ?= false # if true, any undefined auth routes will be set to authRequired, otherwise they default to not required
  # opts.role can be set to a default role too. Or if opts.auth is a string, it will be taken as the default role for everything
  # and if opts.auth is just true, then auth is required for everything, but no particular role
  if opts.auth is true
    opts.secure = true
    opts.auth = {}
  else if typeof opts.auth is 'string'
    opts.secure = true
    opts.role = opts.auth
    opts.auth = {}

  if this._route.indexOf('_log') is -1
    API.log({ msg: 'Mounting ' + opts.route, level: 'info'})
  else if API.settings.log.level is 'debug'
    console.log('Mounting ' + opts.route)

  _this = this
  API.add opts.route,
    get:
      authRequired: if opts.auth?.collection?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.collection?.get is 'string' then opts.auth.collection.get else opts.role
      action: () ->
        return opts.action.collection.get() if typeof opts.action?.collection?.get is 'function'
        return if opts.search then _this.search(this.queryParams) else {}
    post:
      authRequired: if opts.auth?.collection?.post then true else opts.secure
      roleRequired: if typeof opts.auth?.collection?.post is 'string' then opts.auth.collection.post else opts.role
      action: () ->
        return opts.action.collection.post() if typeof opts.action?.collection?.post is 'function'
        return if opts.search then _this.search(this.bodyParams) else _this.insert(this.request.body)
    put:
      authRequired: if opts.auth?.collection?.put then true else opts.secure
      roleRequired: if typeof opts.auth?.collection?.put is 'string' then opts.auth.collection.put else opts.role
      action: () ->
        return if typeof opts.action?.collection?.put is 'function' then opts.action.collection.put() else _this.insert this.request.body
    delete:
      authRequired: if opts.auth?.collection?.delete then true else opts.secure
      roleRequired: if typeof opts.auth?.collection?.delete is 'string' then opts.auth.collection.delete else opts.role
      action: () ->
        return if typeof opts.action?.collection?.delete is 'function' then opts.action.collection.delete() else _this.delete (if this.queryParams.confirm then true else '*'), this.queryParams.history
  API.add opts.route + '/count',
    get:
      authRequired: if opts.auth?.count?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.count?.get is 'string' then opts.auth.count.get else opts.role
      action: () ->
        return if typeof opts.action?.count?.get is 'function' then opts.action.count.get() else _this.count '', this.queryParams
  API.add opts.route + '/keys',
    get:
      authRequired: if opts.auth?.keys?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.keys?.get is 'string' then opts.auth.keys.get else opts.role
      action: () ->
        return if typeof opts.action?.keys?.get is 'function' then opts.action.keys.get() else _this.keys()
  API.add opts.route + '/:key/count',
    get:
      authRequired: if opts.auth?.count?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.count?.get is 'string' then opts.auth.count.get else opts.role
      action: () ->
        return if typeof opts.action?.count?.get is 'function' then opts.action.count.get() else _this.count this.urlParams.key, this.queryParams
  API.add opts.route + '/:key/min',
    get:
      authRequired: if opts.auth?.min?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.min?.get is 'string' then opts.auth.min.get else opts.role
      action: () ->
        return if typeof opts.action?.min?.get is 'function' then opts.action.min.get() else _this.min this.urlParams.key, this.queryParams
  API.add opts.route + '/:key/max',
    get:
      authRequired: if opts.auth?.max?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.max?.get is 'string' then opts.auth.max.get else opts.role
      action: () ->
        return if typeof opts.action?.max?.get is 'function' then opts.action.max.get() else _this.max this.urlParams.key, this.queryParams
  API.add opts.route + '/:key/range',
    get:
      authRequired: if opts.auth?.range?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.range?.get is 'string' then opts.auth.range.get else opts.role
      action: () ->
        return if typeof opts.action?.range?.get is 'function' then opts.action.range.get() else _this.range this.urlParams.key, this.queryParams
  API.add opts.route + '/:key/terms',
    get:
      authRequired: if opts.auth?.terms?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.terms?.get is 'string' then opts.auth.terms.get else opts.role
      action: () ->
        return if typeof opts.action?.terms?.get is 'function' then opts.action.terms.get() else _this.terms this.urlParams.key, this.queryParams.q, this.queryParams.size, this.queryParams.counts is 'true'
    post:
      authRequired: if opts.auth?.terms?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.terms?.get is 'string' then opts.auth.terms.get else opts.role
      action: () ->
        return if typeof opts.action?.terms?.post is 'function' then opts.action.terms.post() else _this.terms this.urlParams.key, this.bodyParams.q, this.bodyParams.size, this.bodyParams.counts is 'true'
  API.add opts.route + '/:id',
    get:
      authRequired: if opts.auth?.item?.get then true else opts.secure
      roleRequired: if typeof opts.auth?.item?.get is 'string' then opts.auth.item.get else opts.role
      action: () ->
        return if typeof opts.action?.item?.get is 'function' then opts.action.item.get() else _this.get this.urlParams.id
    post:
      authRequired: if opts.auth?.item?.post then true else opts.secure
      roleRequired: if typeof opts.auth?.item?.post? is 'string' then opts.auth.item.post else opts.role
      action: () ->
        if typeof opts.action?.item?.post is 'function'
          return opts.action.item.post()
        else
          this.request.body._id = this.urlParams.id
          return _this.update this.request.body
    put:
      authRequired: if opts.auth?.item?.put then true else opts.secure
      roleRequired: if typeof opts.auth?.item?.put is 'string' then opts.auth.item.put else opts.role
      action: () ->
        if typeof opts.action?.item?.put is 'function'
          return opts.action.item.put()
        else
          this.request.body._id = this.urlParams.id
          return _this.insert this.request.body
    delete:
      authRequired: if opts.auth?.item?.delete then true else opts.secure
      roleRequired: if typeof opts.auth?.item?.delete is 'string' then opts.auth.item.delete else opts.role
      action: () ->
        return if typeof opts.action?.item?.delete is 'function' then opts.action.item.delete() else _this.remove this.urlParams.id

### query formats that can be accepted:
    'A simple string to match on'
    'statement:"A more complex" AND difficult string' - which will be used as is to ES as a query string
    '?q=query params directly as string'
    {"q":"object of query params"} - must contain at least q or source as keys to be identified as such
    {"must": []} - a list of must queries, in full ES syntax, which will be dropped into the query filter (works for "should" as well)
    {"object":"of key/value pairs, all of which must match"} - so this is an AND terms match (.exact will be added where not present on keys) - if keys do not point to strings, they will be assumed to be named ES queries that can drop into the bool
    ["list","of strings to OR match on"] - this is an OR query strings match UNLESS strings contain : then mapped to terms matches
    [{"list":"of objects to OR match"}] - so a set of OR terms matches (.exact will be added if objects) - if objects are not key: string they are assumed to be full ES queries that can drop into the bool

    Keys can use dot notation, and can use .exact so that terms match on full terms e.g. "Mark MacGillivray" rather than partials

    Options that can be included:
    If options is true, the query will be adjusted to sort by createdAt descending, so returning the newest first (it sets newest:true, see below)
    If options is string 'random' it will convert the query to be a random order
    If options is a number it will be assumed to be the size parameter
    Otherwise options should be an object (and the above can be provided as keys, "newest", "random")
    If newest is true the query will have a sort desc on createdAt. If false, sort will be asc
    If "random" key is provided, "seed" can be provided too if desired, for seeded random queries
    If "restrict" is provided, should point to list of ES queries to add to the and part of the query filter
    Any other keys in the options object should be directly attributable to an ES query object
    TODO can add more conveniences for passing options in here, such as simplified terms, etc.
###
API.collection._translate = (q, opts) ->
  console.log('Translating query',q,opts) if API.settings.log?.level is 'all'
  qry = opts?.query ? {}
  qry.query ?= {}
  if not qry.query? or not qry.query.filtered?
    qry.query = filtered: {query: qry.query, filter: {}}
  qry.query.filtered.filter ?= {}
  qry.query.filtered.filter.bool ?= {}
  qry.query.filtered.filter.bool.must ?= []
  if not qry.query.filtered.query.bool?
    ms = []
    ms.push(qry.query.filtered.query) if not _.isEmpty qry.query.filtered.query
    qry.query.filtered.query = bool: must: ms
  qry.query.filtered.query.bool.must ?= []
  if typeof q is 'object'
    delete q.apikey if q.apikey?
    delete q._ if q._?
    delete q.callback if q.callback?
    # some URL params that may be commonly used in this API along with valid ES URL query params will be removed here by default too
    # this makes it easy to handle them in routes whilst also just passing the whole queryParams object into this translation method and still get back a valid ES query
    delete q.key if q.key?
    delete q.counts if q.counts?
    if JSON.stringify(q).indexOf('[') is 0
      qry.query.filtered.filter.bool.should = []
      for m in q
        if typeof m is 'object' and m?
          for k of m
            if typeof m[k] is 'string'
              tobj = term:{}
              tobj.term[k.replace('.exact','')+'.exact'] = m[k] # TODO is it worth checking mapping to see if .exact is used by it...
              qry.query.filtered.filter.bool.should.push tobj
            else if typeof m[k] in ['number','boolean']
              qry.query.filtered.query.bool.should.push {query_string:{query:k + ':' + m[k]}}
            else if m[k]?
              qry.query.filtered.filter.bool.should.push m[k]
        else if typeof m is 'string'
          qry.query.filtered.query.bool.should ?= []
          qry.query.filtered.query.bool.should.push query_string: query: m
    else if q.query?
      qry = q # assume already a query
    else if q.source?
      qry = JSON.parse(q.source) if typeof q.source is 'string'
      qry = q.source if typeof q.source is 'object'
      if not opts?
        opts = q
        delete opts.source
    else if q.q?
      qry.query.filtered.query.bool.must.push query_string: query: q.q
      opts ?= {}
      for o of q
        opts[o] ?= q[o] if o not in ['q']
    else
      if q.must?
        qry.query.filtered.filter.bool.must = q.must
      if q.should?
        qry.query.filtered.filter.bool.should = q.should
      if q.must_not?
        qry.query.filtered.filter.bool.must_not = q.must_not
      for y of q # an object where every key is assumed to be an AND term search if string, or a named search object to go in to ES
        if y not in ['must','must_not','should']
          if typeof q[y] is 'string'
            tobj = term:{}
            tobj.term[y.replace('.exact','')+'.exact'] = q[y] # TODO is it worth checking mapping to see if .exact is used by it...
            qry.query.filtered.filter.bool.must.push tobj
          else if typeof q[y] in ['number','boolean']
            qry.query.filtered.query.bool.must.push {query_string:{query:y + ':' + q[y]}}
          else if typeof q[y] is 'object'
            qobj = {}
            qobj[y] = q[y]
            qry.query.filtered.filter.bool.must.push qobj
          else if q[y]?
            qry.query.filtered.filter.bool.must.push q[y]
  else if typeof q is 'string'
    if q.indexOf('?') is 0
      qry = q # assume URL query params and just use them as such?
    else if q?
      q = '*' if q is ''
      qry.query.filtered.query.bool.must.push query_string: query: q
  if opts?
    opts = {random:true} if opts is 'random'
    opts = {size:opts} if typeof opts is 'number'
    opts = {newest: true} if opts is true
    if opts.newest is true
      delete opts.newest
      opts.sort = {createdAt:{order:'desc'}}
    else if opts.newest is false
      delete opts.newest
      opts.sort = {createdAt:{order:'asc'}}
    delete opts._ # delete anything that may have come from query params but are not handled by ES
    delete opts.apikey
    if opts.random
      if typeof qry is 'string'
        qry += '&random=true' # the ES module knows how to convert this to a random query
        qry += '&seed=' + opts.seed if opts.seed?
      else
        fq = {function_score: {random_score: {}}}
        fq.function_score.random_score.seed = seed if opts.seed?
        if qry.query.filtered
          fq.function_score.query = qry.query.filtered.query
          qry.query.filtered.query = fq
        else
          fq.function_score.query = qry.query
          qry.query = fq
      delete opts.random
      delete opts.seed
    if opts.and?
      qry.query.filtered.filter.bool.must.push a for a in opts.and
      delete opts.and
    if opts.sort? and typeof opts.sort is 'string' and opts.sort.indexOf(':') isnt -1
      os = {}
      os[opts.sort.split(':')[0]] = {order:opts.sort.split(':')[1]}
      opts.sort = os
    if opts.restrict?
      qry.query.filtered.filter.bool.must.push(rs) for rs in opts.restrict
      delete opts.restrict
    qry[k] = v for k, v of opts
  qry.query.filtered.query = { match_all: {} } if typeof qry is 'object' and qry.query?.filtered?.query? and _.isEmpty(qry.query.filtered.query)
  console.log('Returning translated query',JSON.stringify(qry)) if API.settings.log?.level is 'all'
  return qry

API.collection._dot = (obj, key, value, del) ->
  if typeof key is 'string'
    return API.collection._dot obj, key.split('.'), value, del
  else if key.length is 1 and (value? or del?)
    if del is true or value is '$DELETE'
      if obj instanceof Array
        obj.splice key[0], 1
      else
        delete obj[key[0]]
      return true;
    else
      obj[key[0]] = value # TODO see below re. should this allow writing into multiple sub-objects of a list?
      return true
  else if key.length is 0
    return obj
  else
    if not obj[key[0]]?
      if false
        # check in case obj is a list of objects, and key[0] exists in those objects
        # if so, return a list of those values.
        # Keep order of the list? e.g for objects not containing the key, output undefined in the list space where value would have gone?
        # and can this recurse further? If the recovered items are lists or objecst themselves, go further into them?
        # if so, how would that be represented?
        # and is it possible for this to work at all with value assignment?
      else if value?
        obj[key[0]] = if isNaN(parseInt(key[0])) then {} else []
        return API.collection._dot obj[key[0]], key.slice(1), value, del
      else
        return undefined
    else
      return API.collection._dot obj[key[0]], key.slice(1), value, del



################################################################################

import Future from 'fibers/future'

API.add 'collection/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.collection.test(this.queryParams.verbose)

API.collection.test = (verbose) ->
  result = {passed:[],failed:[]}

  console.log('Starting collection test') if API.settings.dev

  try
    tc = new API.collection {index:API.settings.es.index + '_test',type:'collection'}
    tc.delete true # get rid of anything that could be lying around from old tests
    tc.map()

  result.recs = [
    {_id:1,hello:'world',lt:1},
    {_id:2,goodbye:'world',lt:2},
    {goodbye:'world',hello:'sunshine',lt:3},
    {goodbye:'marianne',hello:'sunshine',lt:4}
  ]

  tests = [
    () -> #0
      console.log 0
      tc.insert(r) for r in result.recs
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.count = tc.count()
      return result.count is result.recs.length
    () -> #1
      console.log 1
      result.search = tc.search()
      result.stringSearch = tc.search 'goodbye:"marianne"'
      return result.stringSearch?.hits?.total is 1
    () -> #2
      console.log 2
      result.objectSearch = tc.search {hello:'sunshine'}
      return result.objectSearch?.hits?.total is 2
    () -> #3
      result.idFind = tc.find(1)
      return typeof result.idFind is 'object'
    () -> #4
      result.strFind = tc.find 'goodbye:"marianne"'
      return typeof result.strFind is 'object'
    () -> #5
      result.objFind = tc.find {goodbye:'marianne'}
      return typeof result.objFind is 'object'
    () -> #6
      result.objFindMulti = tc.find {goodbye:'world'}
      return typeof result.objFind is 'object'
    () -> #7
      result.each = tc.each 'goodbye:"world"', () -> return
      return result.each is 2
    () -> #8
      result.update = tc.update {hello:'world'}, {goodbye:'world'}
      return result.update is 1
    () -> #9
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.retrieveUpdated = tc.find({hello:'world'})
      return result.retrieveUpdated.goodbye is 'world'
    () -> #10
      result.goodbyes = tc.count(undefined,'goodbye:"world"')
      return result.goodbyes is 3
    () -> #11
      result.lessthan3 = tc.search 'lt:<3'
      return result.lessthan3.hits.total is 2
    () -> #12
      result.remove1 = tc.remove(1)
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      return result.remove1 is true
    () -> #13
      result.helloWorlds = tc.count undefined, {hello:'world'}
      return result.helloWorlds is 0
    () -> #14
      result.remove2 = tc.remove {hello:'sunshine'}
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      return result.remove2 is 2
    () -> #15
      result.remaining = tc.count()
      return result.remaining is 1
    () -> #16
      result.removeLast = tc.remove(2)
      return result.removeLast is true
    () -> #17
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      return tc.count() is 0
  ]

  # TODO add tests for searching with [ TO ]
  # also test for updating with dot.notation and updating things to false or undefined
  # and updating things within objects that do not yet exist, or updating things in lists with numbered dot notation
  # also add a test to read and maybe set the mapping, get terms, and do random search, as tests of the underlying es functions too

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending collection test') if API.settings.dev

  return result

