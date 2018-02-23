

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
    return
      statusCode: 200
      headers:
        'Content-Type': 'text/' + this.queryParams.format ? 'plain'
      body: API.http.phantom this.queryParams.url, this.queryParams.delay ? 1000

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




_save = (lookup,type='cache',content) ->
  return undefined if API.settings.cache is false
  cc = new API.collection index: API.settings.es.index + "_cache", type: type
  lookup = JSON.stringify(lookup) if typeof lookup not in ['string','number','boolean']
  lookup = encodeURIComponent lookup
  if typeof content is 'string'
    try
      cc.insert lookup: lookup, string: content
      return true
    catch
      return false
  else if typeof content is 'boolean'
    try
      cc.insert lookup: lookup, bool: content
      return true
    catch
      return false
  else if typeof content is 'number'
    try
      cc.insert lookup: lookup, number: content
      return true
    catch
      return false
  else
    try
      cc.insert lookup: lookup, content: content
      return true
    catch
      try
        cc.insert lookup: lookup, string: JSON.stringify(content)
        return true
      catch
        return false

API.http.cache = (lookup,type='cache',content,refresh=0) ->
  return _save(lookup, type, content) if content?
  return undefined if API.settings.cache is false
  cc = new API.collection index: API.settings.es.index + "_cache", type: type
  try
    lookup = JSON.stringify(lookup) if typeof lookup not in ['string','number']
    fnd = 'lookup.exact:"' + encodeURIComponent(lookup) + '"'
    if typeof refresh is 'number' and refresh isnt 0
      d = new Date()
      fnd += ' AND createdAt:>' + d.setDate(d.getDate() - refresh)
    res = cc.find fnd, true
    if res?.string?
      try
        parsed = JSON.parse res.string
        API.log {msg:'Returning parsed string result from cache', lookup:lookup, type:type}
        return parsed
      catch
        API.log {msg:'Returning string result from cache', lookup:lookup, type:type}
        return res.string
    else if res?.bool?
      API.log {msg:'Returning object boolean result from cache', lookup:lookup, type:type}
      return res.bool
    else if res?.number?
      API.log {msg:'Returning object number result from cache', lookup:lookup, type:type}
      return res.number
    else if res?.content?
      API.log {msg:'Returning object content result from cache', lookup:lookup, type:type}
      return res.content
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

_phantom = (url,delay=1000,callback) ->
  if typeof delay is 'function'
    callback = delay
    delay = 1000
  return callback(null,'') if not url? or typeof url isnt 'string'
  API.log('starting phantom retrieval of ' + url)
  url = 'http://' + url if url.indexOf('http') is -1
  _ph = undefined
  _page = undefined
  _redirect = undefined
  _fail = undefined
  ppath = if fs.existsSync('/usr/bin/phantomjs') then '/usr/bin/phantomjs' else '/usr/local/bin/phantomjs'
  phantom.create(['--ignore-ssl-errors=true','--load-images=false','--cookies-file=./cookies.txt'],{phantomPath:ppath})
    .then((ph) ->
      _ph = ph
      #API.log('creating page')
      return ph.createPage()
    )
    .then((page) ->
      _page = page
      page.setting('resourceTimeout',3000)
      page.setting('loadImages',false)
      page.setting('userAgent','Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36')
      #API.log('retrieving page ' + url)
      page.property('onResourceRequested',(requestData, request) ->
        if (/http:\/\/.+?\.css/gi).test(requestData['url']) or requestData.headers['Content-Type'] is 'text/css'
          API.log('not getting css at ' + requestData['url'])
          request.abort()
      )
      page.property('onResourceReceived',(resource) ->
        if url is resource.url and resource.redirectURL
          _redirect = resource.redirectURL
      )
      return page.open(url)
    )
    .then((status) ->
      if _redirect
        #API.log('redirecting to ' + _redirect)
        _page.close()
        _ph.exit()
        _phantom(_redirect,delay,callback)
      else if status is 'fail'
        _fail = true
      else
        #API.log('retrieving content');
        future = new Future()
        Meteor.setTimeout (() -> future.return()), delay
        future.wait()
        return _page.property('content')
    )
    .then((content) ->
      if _fail is true or not content.length?
        API.log('could not get content, fail is ' + _fail + ' and content length is ' + content.length)
        return callback(null,'')
      else if content.length < 200 and delay <= 11000
        delay += 5000
        _page.close()
        _ph.exit()
        redirector = undefined
        #API.log('trying again with delay ' + delay)
        _phantom(url,delay,callback)
      else
        #API.log('got content')
        _page.close()
        _ph.exit()
        _redirect = undefined
        return callback(null,content)
    )
    .catch((error) ->
      API.log({msg:'phantom errored',error:error})
      _page.close()
      _ph.exit()
      _redirect = undefined
      return callback(null,'')
    )

API.http.phantom = Meteor.wrapAsync(_phantom)
