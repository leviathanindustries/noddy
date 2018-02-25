

# elasticsearch API
# because the logger uses ES to log logs, ES uses console.log at some points where other things should use API.log
# NOTE: if an index/type can be public, just make it public and have nginx route to it directly, saving app load.

import Future from 'fibers/future'
import fs from 'fs'

API.es = {}

if not API.settings.es?
  console.log 'ES WARNING - ELASTICSEARCH SEEMS TO BE REQUIRED BUT SETTINGS HAVE NOT BEEN PROVIDED.'
else
  try
    API.settings.es.url = [API.settings.es.url] if typeof API.settings.es.url is 'string'
    for url in API.settings.es.url
      s = HTTP.call 'GET', url
    if API.settings.log?.level is 'debug'
      console.log 'ES confirmed ' + API.settings.es.url + ' is reachable'
  catch err
    console.log 'ES FAILURE - INSTANCE AT ' + API.settings.es.url + ' APPEARS TO BE UNREACHABLE.'
    console.log err
API.settings.es.index ?= API.settings.name ? 'noddy'

'''API.add 'es_reindex/:index/:type',
  get:
    authRequired: 'root'
    action: () ->
      Meteor.setTimeout (() -> API.es.reindex this.urlParams.index, this.urlParams.type, undefined, this.queryParams.rename, not this.queryParams.delete? ), 1
      return true'''

_esr = 'es'
for r in [0,1,2]
  _esr += '/:r' + r
  API.add _esr,
    get:
      authOptional: true
      action: () -> return API.es.action this.user, 'GET', this.urlParams, this.queryParams
    post:
      authOptional: true
      action: () -> return API.es.action this.user, 'POST', this.urlParams, this.queryParams, this.request.body
    put:
      authRequired: true
      action: () -> return API.es.action this.user, 'PUT', this.urlParams, this.queryParams, this.request.body
    delete:
      authRequired: true
      action: () -> return API.es.action this.user, 'DELETE', this.urlParams, this.queryParams, this.request.body

API.es.action = (uacc, action, urlp, params, data, refresh) ->
  if urlp.r0 is '_indexes'
    return API.es.indexes()
  else if urlp.r1 is '_types'
    return API.es.types(urlp.r0)
  else if urlp.r0 is '_reindex' and urlp.r1?
    if API.accounts.auth 'root', uacc
      types = if urlp.r2? then [urlp.r2] else API.es.types urlp.r1
      Meteor.setTimeout (() -> API.es.reindex(urlp.r1, type, undefined, params?.rename, not params?.delete?) for type in types ), 1
      return true
    else
      return 401
  else
    rt = ''
    rt += '/' + urlp[up] for up of urlp
    rt += '/_search' if action in ['GET','POST'] and rt.indexOf('/_') is -1 and rt.split('/').length <= 3
    rt += '?'
    rt += op + '=' + params[op] + '&' for op of params if params
    auth = API.settings.es.auth
    # if not dev and auth not explicitly set all true, then all access defaults false
    # if in dev, then any query onto _dev indices will default true, unless auth is an object, and anything else is still false
    allowed = if auth isnt true then (typeof auth isnt 'object' and urlp.r0.indexOf('_dev') isnt -1 and API.settings.dev) else false
    if typeof auth is 'object' and urlp.r0 and auth[urlp.r0]?
      auth = auth[urlp.r0]
      if typeof auth is 'object' and urlp.r1 and auth[urlp.r1]?
        auth = auth[urlp.r1]
        if typeof auth is 'object' and urlp.r2 and auth[urlp.r2]?
          auth = auth[urlp.r2]
    allowed = true if auth is true
    if not allowed # check if user has specific permissions
      user = if typeof uacc is 'object' then uacc else API.accounts.retrieve uacc
      allowed = user? and API.accounts.auth 'root', user # root gets access anyway
      if not allowed
        ort = urlp.r0
        ort += '_' + urlp.r1 if urlp.r1
        if (action is 'GET' or (action is 'POST' and urlp.r2 is '_search')) and API.accounts.auth ort + '.read', user
          allowed = true
        else if action in ['POST','PUT'] and API.accounts.auth ort + '.edit', user
          allowed = true
        else if action is 'DELETE' and API.accounts.auth ort + '.owner', user
          allowed = true
    return if allowed then API.es.call(action, rt, data, refresh) else 401

# track if we are waiting on retry to connect http to ES (when it is busy it takes a while to respond)
API.es._waiting = false
API.es._retries = {
  baseTimeout: 100,
  maxTimeout: 5000,
  times: 10,
  shouldRetry: (err,res,cb) ->
    rt = false
    try
      serr = err.toString()
      rt = serr.indexOf('ECONNREFUSED') isnt -1 or serr.indexOf('ECONNRESET') isnt -1 or serr.indexOf('socket hang up') isnt -1 or (typeof err?.response?.statusCode is 'number' and err.response.statusCode >= 500)
    catch
      rt = true
    if rt and API.settings.dev # cannot API.log because will already be hitting ES access problems
      console.log 'Waiting for Retry on ES connection'
      try console.log serr
      try console.log err?.response?.statusCode
    API.es._waiting = rt
    cb null, rt
}

API.es.refresh = (index, url) ->
  try
    API.log 'Refreshing index ' + index
    h = API.es.call 'POST', index + '/_refresh', undefined, undefined, undefined, undefined, undefined, url
    return true
  catch err
    return false

API.es._reindexing = false
API.es.reindex = (index, type, mapping=API.es._mapping, rename, del, change, fromurl=API.settings.es.url, tourl=API.settings.es.url) ->
  fromurl = fromurl[Math.floor(Math.random()*fromurl.length)] if Array.isArray fromurl
  tourl = tourl[Math.floor(Math.random()*fromurl.length)] if Array.isArray tourl
  return false if not index? or not type?
  # index names will be treated as specific
  # and only handle indexes in the API.settings.es.index namespace - or allow move from others? handy for moving old systems to new
  API.es._reindexing = index + '/' + type
  toindex = if rename? then rename.split('/')[0] else index
  totype = if rename? and rename.indexOf('/') isnt -1 then rename.split('/')[1] else type
  processed = 0
  try
    try pim = RetryHttp.call 'PUT', tourl + '/temp_reindex_' + toindex, {retry:API.es._retries}
    pitm = RetryHttp.call 'PUT', tourl + '/temp_reindex_' + toindex + '/_mapping/' + totype, {data: mapping, retry:API.es._retries}
    ret = RetryHttp.call 'POST', fromurl + '/' + index + '/' + type + '/_search?search_type=scan&scroll=1m', {data:{query: { match_all: {} }, size: 5000 }, retry:API.es._retries}
    if ret.data?._scroll_id?
      res = RetryHttp.call 'GET', fromurl + '/_search/scroll?scroll=1m&scroll_id=' + ret.data._scroll_id, {retry:API.es._retries}
      while (res?.data?.hits?.hits? and res.data.hits.hits.length)
        processed += res.data.hits.hits.length
        pkg = ''
        for row in res.data.hits.hits
          pkg += JSON.stringify({"index": {"_index": 'temp_reindex_' + toindex, "_type": totype, "_id": row._source._id }}) + '\n'
          if change?
            if typeof change is 'function'
              try rec._source = change rec._source
            else if typeof change is 'string'
              try
                fn = if change.indexOf('API.') is 0 then API else global
                fn = fn[f] for f in change.replace('API.','').split('.')
                rec._source = fn.apply this, rec._source # or maybe just fn rec._source is enough?
          pkg += JSON.stringify(row._source) + '\n'
        hp = RetryHttp.call 'POST', tourl + '/_bulk', {content:pkg, headers:{'Content-Type':'text/plain'},retry:API.es._retries}
        try refreshed = RetryHttp.call 'POST', tourl + '/temp_reindex_' + toindex + '/_refresh', {retry:API.es._retries}
        pkg = ''
        res = RetryHttp.call 'GET', fromurl + '/_search/scroll?scroll=1m&scroll_id=' + res.data._scroll_id, {retry:API.es._retries}
  catch err
    API.log {msg: 'Reindex failed at copy step for ' + index + ' ' + type, level:'warn', notify:true, error: err}
    processed = false
  if processed isnt false
    if del isnt false
      deleted_original = RetryHttp.call 'DELETE', fromurl + '/' + index + '/' + type, {retry:API.es._retries}
    try
      try nim = RetryHttp.call 'PUT', tourl + '/' + toindex, {retry:API.es._retries}
      nitm = RetryHttp.call 'PUT', tourl + '/' + toindex + '/_mapping/' + totype, {data: mapping, retry:API.es._retries}
      ret = RetryHttp.call 'POST', tourl + '/temp_reindex_' + toindex + '/' + totype + '/_search?search_type=scan&scroll=1m', {data:{query: { match_all: {} }, size: 5000 }, retry:API.es._retries}
      if ret.data?._scroll_id?
        res = RetryHttp.call 'GET', tourl + '/_search/scroll?scroll=1m&scroll_id=' + ret.data._scroll_id, {retry:API.es._retries}
        while (res?.data?.hits?.hits? and res.data.hits.hits.length)
          pkg = ''
          for row in res.data.hits.hits
            pkg += JSON.stringify({"index": {"_index": toindex, "_type": totype, "_id": row._source._id }}) + '\n'
            pkg += JSON.stringify(row._source) + '\n'
          hp = RetryHttp.call 'POST', tourl + '/_bulk', {content:pkg, headers:{'Content-Type':'text/plain'},retry:API.es._retries}
          try refreshed = RetryHttp.call 'POST', tourl + '/' + toindex + '/_refresh', {retry:API.es._retries}
          pkg = ''
          res = RetryHttp.call 'GET', tourl + '/_search/scroll?scroll=1m&scroll_id=' + res.data._scroll_id, {retry:API.es._retries}
      deleted_temp = RetryHttp.call 'DELETE', tourl + '/temp_reindex_' + toindex, {retry:API.es._retries}
      API.log {msg: 'Reindexed ' + index + ' ' + type + ' with ' + processed + ' records', level:'warn', notify:true}
    catch err
      processed = false
      API.log {msg: 'Reindex failed at recreate step for ' + index + ' ' + type, level:'warn', notify:true, error: err}
  API.es._reindexing = false
  return processed

API.es.map = (index, type, mapping, overwrite, url=API.settings.es.url) ->
  url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  console.log('ES checking mapping for ' + index + (if API.settings.dev and index.indexOf('_dev') is -1 then '_dev') + ' ' + type) if API.settings.log?.level is 'debug'
  try
    try RetryHttp.call 'PUT', url + '/' + index + (if API.settings.dev and index.indexOf('_dev') is -1 then '_dev'), {retry:API.es._retries}
    maproute = index + (if API.settings.dev and index.indexOf('_dev') is -1 then '_dev') + '/_mapping/' + type
    try
      m = RetryHttp.call 'GET', url + '/' + maproute, {retry:API.es._retries}
      overwrite = true if _.isEmpty(m.data)
    catch
      overwrite = true
    if overwrite
      if not mapping? and API.settings.es.mappings
        maps
        if typeof API.settings.es.mappings is 'object'
          maps = API.settings.es.mappings
        else
          try
            if API.settings.es.mappings.indexOf('http') is 0
              maps = RetryHttp.call('GET', API.settings.es.mappings, {retry:API.es._retries}).data
            else
              maps = JSON.parse fs.readFileSync(API.settings.es.mappings).toString()
        if maps?[index]?[type]?
          mapping = maps[index][type]
        else if maps?[type]?
          mapping = maps[type]
      if not mapping? and API.settings.es.mapping
        if typeof API.settings.es.mapping is 'object'
          mapping = API.settings.es.mapping
        else
          try
            if API.settings.es.mappings.indexOf('http') is 0
              mapping = HTTP.call('GET', API.settings.es.mapping).data
            else
              mapping = JSON.parse fs.readFileSync(API.settings.es.mapping).toString()
      if not mapping?
        try mapping = API.es._mapping
      if not mapping?
        try mapping = JSON.parse fs.readFileSync(process.env.PWD + '/public/mapping.json').toString()
      if mapping?
        RetryHttp.call 'PUT', url + '/' + maproute, {data: mapping, retry:API.es._retries}
        console.log('ES mapping created') if API.settings.log?.level is 'debug'
      else
        console.log('ES has no mapping available') if API.settings.log?.level is 'debug'
    else
      console.log('ES mapping already exists') if API.settings.log?.level is 'debug'
  catch err
    if API.settings.log?.level is 'debug'
      console.log 'ES MAPPING ERROR'
      console.log err

API.es.mapping = (index='', type='', url=API.settings.es.url) ->
  index += '_dev' if index.length and API.settings.dev and index.indexOf('_dev') is -1
  try
    mp = API.es.call 'GET', index + '/_mapping/' + type, undefined, undefined, undefined, undefined, undefined, url
    return if index.length then (if type.length then mp[index].mappings[type] else mp[index].mappings) else mp
  catch
    return {}

API.es.indexes = (url=API.settings.es.url) ->
  url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  indexes = []
  try indexes.push(m) for m of HTTP.call('GET', url + '/_mapping').data
  return indexes

API.es.types = (index,url=API.settings.es.url) ->
  url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  types = []
  try types.push(t) for t of HTTP.call('GET', url + '/' + index + '/_mapping').data[index].mappings
  return types

API.es.call = (action, route, data, refresh, versioned, scan, scroll='1m', url=API.settings.es.url) ->
  url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  route = '/' + route if route.indexOf('/') isnt 0
  return false if action is 'DELETE' and route.indexOf('/_all') is 0 # disallow delete all
  if API.settings.dev and route.indexOf('_dev') is -1 and route.indexOf('/_') isnt 0
    rpd = route.split '/'
    rpd[1] += '_dev'
    route = rpd.join '/'
  routeparts = route.substring(1, route.length).split '/'

  while routeparts[0] + '/' + routeparts[1] is API.es._reindexing
    future = new Future()
    Meteor.setTimeout (() -> future.return()), 5000
    future.wait()
  if API.es._waiting
    future = new Future()
    Meteor.setTimeout (() -> future.return()), Math.floor(Math.random()*601+300)
    future.wait()
  API.es._waiting = false

  # API.es.map(routeparts[0],routeparts[1],undefined,undefined,url) if route.indexOf('/_') is -1 and routeparts.length >= 1 and action in ['POST','PUT']
  opts = data:data
  route = API.es.random(route) if route.indexOf('source') isnt -1 and route.indexOf('random=true') isnt -1
  route += (if route.indexOf('?') is -1 then '?' else '&') + 'version=' + versioned if versioned?
  if scan is true
    route += (if route.indexOf('?') is -1 then '?' else '&') + 'search_type=scan&scroll=' + scroll
  else if scan?
    route = '/_search/scroll?scroll=' + scroll + '&scroll_id=' + scan
  try
    try
      if action is 'POST' and data?.query? and data.sort? and routeparts.length > 1
        skey = _.keys(data.sort)[0]
        delete opts.data.sort if JSON.stringify(API.es.mapping(routeparts[0],routeparts[1])).indexOf(skey) is -1
    opts.retry = API.es._retries
    ret = RetryHttp.call action, url + route, opts
    API.es.refresh('/' + routeparts[0], url) if refresh and action in ['POST','PUT']
    ld = JSON.parse(JSON.stringify(ret.data))
    ld.hits?.NOTE = 'Results length reduced from ' + ld.hits.hits.length + ' to 1 for logging example, does not affect output'
    ld.hits?.hits = ld.hits?.hits.splice(0,1)
    if route.indexOf('_log') is -1
      API.log msg:'ES query info', options:opts, result: ld, level: 'all'
    else if API.settings.log?.level is 'all'
      console.log('ES SEARCH DEBUG INFO\n' + JSON.stringify(opts),'\n',JSON.stringify(ld),'\n')
    return ret.data
  catch err
    # if versioned and versions don't match, there will be a 409 thrown here - this should be handled in some way, here or in collection
    # https://www.elastic.co/blog/elasticsearch-versioning-support
    lg = level: 'debug', msg: 'ES error, but may be OK, 404 for empty lookup, for example', action: action, url: url, route: route, opts: opts, error: err.toString()
    if err.response?.statusCode isnt 404 and route.indexOf('_log') is -1
      API.log lg
    if API.settings.log?.level is 'all'
      console.log lg
      console.log JSON.stringify(opts)
      console.log JSON.stringify(err)
      try console.log err.toString()
    return undefined

API.es.random = (route) ->
  try
    fq =
      function_score:
        query: undefined # set below
        random_score: {} # "seed" : 1376773391128418000 }
    route = route.replace 'random=true', ''
    if route.indexOf('seed=') isnt -1
      seed = route.split('seed=')[0].split('&')[0]
      fq.function_score.random_score.seed = seed
      route = route.replace 'seed=' + seed, ''
    rp = route.split 'source='
    start = rp[0]
    qrp = rp[1].split '&'
    qr = JSON.parse decodeURIComponent(qrp[0])
    rest = if qrp.length > 1 then qrp[1] else ''
    if qr.query.filtered
      fq.function_score.query = qr.query.filtered.query
      qr.query.filtered.query = fq
    else
      fq.function_score.query = qr.query
      qr.query = fq
    qr = encodeURIComponent JSON.stringify(qr)
    return start + 'source=' + qr + '&' + rest
  catch
    return route

API.es.terms = (index, type, key, size=100, counts=true, qry, url=API.settings.es.url) ->
  url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  query = if typeof qry is 'object' then qry else { query: { "match_all": {} }, size: 0, facets: {} }
  query.query = { query_string: { query: qry } } if typeof qry is 'string'
  query.facets ?= {}
  query.facets[key] = { terms: { field: key, size: size } }; # TODO need some way to decide if should check on .exact? - collection assumes it so far
  try
    ret = API.es.call 'POST', '/' + index + '/' + type + '/_search', query, undefined, undefined, undefined, undefined, url
    return if counts then ret.facets[key].terms else _.pluck(ret.facets[key].terms,'term')
  catch err
    console.log(err) if API.settings.log?.level is 'debug'
    return []

API.es.import = (index, type, data, bulk=50000, url=API.settings.es.url) ->
  url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  index += '_dev' if API.settings.dev and index.indexOf('_dev') is -1
  rows = if typeof data is 'object' and not Array.isArray(data) and data?.hits?.hits? then data.hits.hits else data
  rows = [rows] if not Array.isArray rows
  if index.indexOf('_log') is -1
    API.log 'Doing bulk import of ' + rows.length + ' rows for ' + index + ' ' + type
  else if API.settings.log?.level in ['all','debug']
    console.log 'Doing bulk import of ' + rows.length + ' rows for ' + index + ' ' + type
  counter = 0
  pkg = ''
  responses = []
  for r of rows
    counter += 1
    row = rows[r]
    row._index += '_dev' if row._index? and row._index.indexOf('_dev') is -1 and API.settings.dev
    meta = {"index": {"_index": (if row._index? then row._index else index), "_type": (if row._type? then row._type else type) }}
    meta.index._id = row._id if row._id?
    pkg += JSON.stringify(meta) + '\n'
    pkg += JSON.stringify(if row._source then row._source else row) + '\n'
    if counter is bulk or parseInt(r) is (rows.length - 1)
      hp = RetryHttp.call 'POST', url + '/_bulk', {content:pkg, headers:{'Content-Type':'text/plain'},retry:API.es._retries}
      responses.push hp
      pkg = ''
      counter = 0
  return {records:rows.length, responses:responses}



API.es.status = () ->
  s = API.es.call 'GET', '/_status'
  status = { cluster: {}, shards: { total: s._shards.total, successful: s._shards.successful }, indices: {} }
  status.indices[i] = { docs: s.indices[i].docs.num_docs, size: Math.ceil(s.indices[i].index.primary_size_in_bytes / 1024 / 1024) } for i of s.indices
  status.cluster = API.es.call 'GET', '/_cluster/health'
  return status



API.es._mapping = {
  "properties": {
    "location": {
      "properties": {
        "geo": {
          "type": "geo_point",
          "lat_lon": true
        }
      }
    },
    "created_date": {
      "type": "date",
      "format" : "yyyy-MM-dd HHmm||yyyy-MM-dd HHmm.ss||date_optional_time"
    },
    "updated_date": {
      "type": "date",
      "format" : "yyyy-MM-dd HHmm||yyyy-MM-dd HHmm.ss||date_optional_time"
    },
    "createdAt": {
      "type": "date",
      "format" : "yyyy-MM-dd HHmm||yyyy-MM-dd HHmm.ss||date_optional_time"
    },
    "updatedAt": {
      "type": "date",
      "format" : "yyyy-MM-dd HHmm||yyyy-MM-dd HHmm.ss||date_optional_time"
    },
    "attachments":{
      "properties": {
        "attachment": {
          "type": "attachment"
        }
      }
    }
  },
  "date_detection": false,
  "dynamic_templates" : [
    {
      "followingdates": {
        "mapping": {
          "type": "date"
          "format": "yyyy-MM-dd HHmm||yyyy-MM-dd HHmm.ss||date_optional_time"
        },
        "path_match": "date*"
      }
    },
    {
      "leadingdates": {
        "mapping": {
          "type": "date",
          "format": "yyyy-MM-dd HHmm||yyyy-MM-dd HHmm.ss||date_optional_time"
        },
        "path_match": "*date"
      }
    },
    {
      "default" : {
        "match" : "*",
        "match_mapping_type": "string",
        "mapping" : {
          "type" : "string",
          "fields" : {
            "exact" : {"type" : "{dynamic_type}", "index" : "not_analyzed", "store" : "no"}
          }
        }
      }
    }
  ]
}
