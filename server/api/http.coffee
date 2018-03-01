

# useful http things, so far include a URL resolver and a phantomjs resolver
# and a simple way for any endpoint (probably the use endpoints) to cache
# results. e.g. if the use/europepmc submits a query to europepmc, it could
# cache the entire result, then check for a cached result on the next time
# it runs the same query. This is probably most useful for queries that
# expect to return singular result objects rather than full search lists.
# the lookup value should be a stringified representation of whatever
# is being used as a query. It could be a JSON object or a URL, or so on.
# It will just get stringified and used to lookup later.

import request from 'request'
import Future from 'fibers/future'
import phantom from 'phantom'
import fs from 'fs'


API.http = {}

API.add 'http/resolve', get: () -> return API.http.resolve this.queryParams.url

API.add 'http/phantom',
  get: () ->
    refresh = if this.queryParams.refresh? then (try(parseInt(this.queryParams.refresh))) else undefined
    res = API.http.phantom this.queryParams.url, this.queryParams.delay ? 1000, refresh
    if typeof res is 'number'
      return res
    else
      return
        statusCode: 200
        headers:
          'Content-Type': 'text/' + this.queryParams.format ? 'plain'
        body: res

API.add 'http/cache',
  get: () ->
    q = if _.isEmpty(this.queryParams) then '' else API.collection._translate this.queryParams
    if typeof q is 'string'
      return API.es.call 'GET', API.settings.es.index + '_cache/_search?' + q.replace('?', '')
    else
      return API.es.call 'POST', API.settings.es.index + '_cache/_search', q

API.add 'http/cache/types',
  get: () ->
    types = []
    mapping = API.es.call 'GET', API.settings.es.index + '_cache/_mapping'
    for m of mapping
      if mapping[m].mappings?
        for t of mapping[m].mappings
          types.push t
    return types

API.add 'http/cache/:type',
  get: () ->
    q = if _.isEmpty(this.queryParams) then '' else API.collection._translate this.queryParams
    if typeof q is 'string'
      return API.es.call 'GET', API.settings.es.index + '_cache/' + this.urlParams.type + '/_search?' + q.replace('?', '')
    else
      return API.es.call 'POST', API.settings.es.index + '_cache/' + this.urlParams.type + '/_search', q

API.add 'http/cache/:types/clear',
  get:
    authRequired: 'root'
    action: () ->
      API.es.call 'DELETE', API.settings.es.index + '_cache' + if this.urlParams.types isnt '_all' then '/' + this.urlParams.types else ''
      return true




API.http._colls = {}
API.http._save = (lookup,type='cache',content) ->
  API.http._colls[type] ?= new API.collection index: API.settings.es.index + "_cache", type: type
  lookup = JSON.stringify(lookup) if typeof lookup not in ['string','number','boolean']
  lookup = encodeURIComponent lookup
  sv = {lookup: lookup, _raw_result: {}}
  if typeof content is 'string'
    sv._raw_result.string = content
  else if typeof content is 'boolean'
    sv._raw_result.bool = content
  else if typeof content is 'number'
    sv._raw_result.number = content
  else
    sv._raw_result.content = content
  saved = API.http._colls[type].insert sv
  if not saved?
    try
      sv._raw_result = {stringify: JSON.stringify content}
      saved = API.http._colls[type].insert sv
  return saved

API.http.cache = (lookup,type='cache',content,refresh=0) ->
  return undefined if API.settings.cache is false
  return API.http._save(lookup, type, content) if content?
  API.http._colls[type] ?= new API.collection index: API.settings.es.index + "_cache", type: type
  try
    lookup = JSON.stringify(lookup) if typeof lookup not in ['string','number']
    fnd = 'lookup.exact:"' + encodeURIComponent(lookup) + '"'
    if typeof refresh is 'number' and refresh isnt 0
      fnd += ' AND createdAt:>' + (Date.now() - refresh)
    res = API.http._colls[type].find fnd, true
    if res?._raw_result?.string?
      API.log {msg:'Returning string result from cache', lookup:lookup, type:type}
      return res._raw_result.string
    else if res?._raw_result?.bool?
      API.log {msg:'Returning object boolean result from cache', lookup:lookup, type:type}
      return res._raw_result.bool
    else if res?._raw_result?.number?
      API.log {msg:'Returning object number result from cache', lookup:lookup, type:type}
      return res._raw_result.number
    else if res?._raw_result?.content?
      API.log {msg:'Returning object content result from cache', lookup:lookup, type:type}
      return res.content
    else if res?._raw_result?.stringify
      try
        parsed = JSON.parse res._raw_result.stringify
        API.log {msg:'Returning parsed stringified content result from cache', lookup:lookup, type:type}
        return parsed
  return undefined

API.http.resolve = (url) ->
  cached = API.http.cache url, 'http_resolve'
  if cached
    return cached
  else
    try
      try
        resolved = API.use.crossref.resolve(url) if url.indexOf('10') is 0 or url.indexOf('doi.org/') isnt -1
      resolve = (url, callback) ->
        API.log 'Resolving ' + url
        request.head url, {jar:true, headers: {'User-Agent':'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36'}}, (err, res, body) ->
          callback null, (if not res? or (res.statusCode? and res.statusCode > 399) then false else res.request.uri.href)
      aresolve = Meteor.wrapAsync resolve
      resolved = aresolve resolved ? url
      API.http.cache(url, 'http_resolve', resolved) if resolved
      return resolved ? undefined
    catch
      return undefined


# old resolve notes:
# using external dependency to call request.head because Meteor provides no way to access the final url from the request module, annoyingly
# https://secure.jbs.elsevierhealth.com/action/getSharedSiteSession?rc=9&redirect=http%3A%2F%2Fwww.cell.com%2Fcurrent-biology%2Fabstract%2FS0960-9822%2815%2901167-7%3F%26np%3Dy&code=cell-site
# redirects (in a browser but in code gets stuck in loop) to:
# http://www.cell.com/current-biology/abstract/S0960-9822(15)01167-7?&np=y
# many sites like elsevier ones on cell.com etc even once resolved will actually redirect the user again
# this is done via cookies and url params, and does not seem to accessible programmatically in a reliable fashion
# so the best we can get for the end of a redirect chain may not actually be the end of the chain that a user
# goes through, so FOR ACTUALLY ACCESSING THE CONTENT OF THE PAGE PROGRAMMATICALLY, USE THE phantom.get method instead
# here is an odd one that seems to stick forever:
# https://kclpure.kcl.ac.uk/portal/en/publications/superior-temporal-activation-as-a-function-of-linguistic-knowledge-insights-from-deaf-native-signers-who-speechread(4a9db251-4c8e-4759-b0eb-396360dc897e).html

_phantom = (url,delay=1000,refresh=86400000,callback) ->
  if typeof refresh is 'function'
    callback = refresh
    refresh = 86400000
  if typeof delay is 'function'
    callback = delay
    delay = 1000
  return callback(null,'') if not url? or typeof url isnt 'string'
  cached = API.http.cache url, 'phantom_get', undefined, refresh
  if cached?
    return callback(null,cached)
  API.log('starting phantom retrieval of ' + url)
  url = 'http://' + url if url.indexOf('http') is -1
  _ph = undefined
  _page = undefined
  _info = {}
  ppath = if fs.existsSync('/usr/bin/phantomjs') then '/usr/bin/phantomjs' else '/usr/local/bin/phantomjs'
  phantom.create(['--ignore-ssl-errors=true','--load-images=false','--cookies-file=./cookies.txt'],{phantomPath:ppath})
    .then((ph) ->
      _ph = ph
      return ph.createPage()
    )
    .then((page) ->
      _page = page
      page.setting('resourceTimeout',5000)
      page.setting('loadImages',false)
      page.setting('userAgent','Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36')
      page.on('onResourceRequested',true,(requestData, request) -> request.abort() if (/\/\/.+?\.css/gi).test(requestData['url']) or requestData.headers['Content-Type'] is 'text/css')
      page.on('onResourceError',((err) -> _info.err = err))
      page.on('onResourceReceived',((resource) -> _info.resource = resource)) # _info.redirect = resource.redirectURL if resource.url is url))
      return page.open(url)
    )
    .then((status) ->
      future = new Future()
      Meteor.setTimeout (() -> future.return()), delay
      future.wait()
      _info.status = status
      return _page.property('content')
    )
    .then((content) ->
      _page.close()
      _ph.exit()
      _ph = undefined
      _page = undefined
      if _info?.resource?.redirectURL? and _info?._resource?.url is url
        API.log('redirecting ' + url + ' to ' + _redirect)
        ru = _info.resource.redirectURL
        _info = {}
        _phantom(ru,delay,callback)
      else if _info.status is 'fail' or not content?.length? or _info.err?.status > 399
        API.log('could not get content for ' + url + ', phantom status is ' + _info.status + ' and response status code is ' + _info.err?.status + ' and content length is ' + content.length)
        sc = _info.err?.status ? 0
        _info = {}
        return callback(null,sc)
      else if content?.length < 200 and delay <= 11000
        API.log('trying ' + url + ' again with delay ' + delay)
        delay += 5000
        _info = {}
        _phantom(url,delay,refresh,callback)
      else
        API.http.cache url, 'phantom_get', content
        _info = {}
        return callback(null,content)
    )
    .catch((error) ->
      API.log({msg:'Phantom errorred for ' + url, error:error})
      _page.close()
      _ph.exit()
      _ph = undefined
      _page = undefined
      _info = {}
      return callback(null,'')
    )

API.http.phantom = Meteor.wrapAsync(_phantom)


