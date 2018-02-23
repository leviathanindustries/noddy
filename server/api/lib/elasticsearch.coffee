

# elasticsearch API
# because the logger uses ES to log logs, ES uses console.log at some points where other things should use API.log
# NOTE: if an index/type can be public, just make it public and have nginx route to it directly, saving app load.

import fs from 'fs'

API.es = {}

if not API.settings.es?
  console.log 'ES WARNING - ELASTICSEARCH SEEMS TO BE REQUIRED BUT SETTINGS HAVE NOT BEEN PROVIDED.'
else
  try
    s = HTTP.call 'GET', API.settings.es.url
    if API.settings.log?.level is 'debug'
      console.log 'ES confirmed ' + API.settings.es.url + ' is reachable'
      console.log s.data
  catch err
    console.log 'ES FAILURE - INSTANCE AT ' + API.settings.es.url + ' APPEARS TO BE UNREACHABLE.'
    console.log err
API.settings.es.index ?= API.settings.name ? 'noddy'

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

# TODO add other actions in addition to map, for exmaple _reindex would be useful
# how about _alias? And check for others too, and add here

API.es.refresh = (index, url) ->
  try
    API.log 'Refreshing index ' + index
    h = API.es.call 'POST', index + '/_refresh', undefined, undefined, undefined, undefined, undefined, url
    return true
  catch err
    return false

API.es.map = (index, type, mapping, overwrite, url=API.settings.es.url) ->
  console.log('ES checking mapping for ' + index + (if API.settings.dev then '_dev') + ' ' + type) if API.settings.log?.level is 'debug'
  try
    try HTTP.call 'PUT', url + '/' + index + (if API.settings.dev then '_dev')
    maproute = index + (if API.settings.dev then '_dev') + '/_mapping/' + type
    try
      m = HTTP.call 'GET', url + '/' + maproute
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
              maps = HTTP.call('GET', API.settings.es.mappings).data
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
        HTTP.call 'PUT', url + '/' + maproute, data: mapping
        console.log('ES mapping created') if API.settings.log?.level is 'debug'
      else
        console.log('ES has no mapping available') if API.settings.log?.level is 'debug'
    else
      console.log('ES mapping already exists') if API.settings.log?.level is 'debug'
  catch err
    if API.settings.log?.level is 'debug'
      console.log 'ES MAPPING ERROR'
      console.log err

API.es.mapping = (index, type, url=API.settings.es.url) ->
  index += '_dev' if API.settings.dev and index.indexOf('_dev') is -1
  return API.es.call('GET', index + '/_mapping/' + type, undefined, undefined, undefined, undefined, undefined, url)[index].mappings[type]

API.es.call = (action, route, data, refresh, versioned, scan, scroll='1m', url=API.settings.es.url) ->
  route = '/' + route if route.indexOf('/') isnt 0
  return false if action is 'DELETE' and route.indexOf('/_all') is 0 # disallow delete all
  if API.settings.dev and route.indexOf('_dev') is -1 and route.indexOf('/_') isnt 0
    rpd = route.split '/'
    rpd[1] += '_dev'
    route = rpd.join '/'
  routeparts = route.substring(1, route.length).split '/'
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
    ret = HTTP.call action, url + route, opts
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
  index += '_dev' if API.settings.dev and index.indexOf('_dev') is -1
  rows = if typeof data is 'object' and not Array.isArray(data) and data?.hits?.hits? then data.hits.hits else data
  rows = [rows] if not Array.isArray rows
  API.log 'Doing bulk import of ' + rows.length + ' rows for ' + index + ' ' + type
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
      hp = HTTP.call 'POST', url + '/_bulk', {content:pkg, headers:{'Content-Type':'text/plain'}}
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
      "format" : "yyyy-MM-dd mmss||date_optional_time"
    },
    "updated_date": {
      "type": "date",
      "format" : "yyyy-MM-dd mmss||date_optional_time"
    },
    "createdAt": {
      "type": "date",
      "format" : "yyyy-MM-dd mmss||date_optional_time"
    },
    "updatedAt": {
      "type": "date",
      "format" : "yyyy-MM-dd mmss||date_optional_time"
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
          "format": "yyyy-MM-dd mmss||date_optional_time"
        },
        "path_match": "date*"
      }
    },
    {
      "leadingdates": {
        "mapping": {
          "type": "date",
          "format": "yyyy-MM-dd mmss||date_optional_time"
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
