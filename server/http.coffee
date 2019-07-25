

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
import puppeteer from 'puppeteer'
import fs from 'fs'
import formdata from 'form-data'
import stream from 'stream'
#import phantom from 'phantom'

API.http = {}

API.add 'http/resolve', get: () -> return API.http.resolve this.queryParams.url, this.queryParams.refresh

API.add 'http/puppeteer',
  get: () ->
    refresh = if this.queryParams.refresh? then (try(parseInt(this.queryParams.refresh))) else undefined
    url = this.queryParams.url
    url += if url.indexOf('?') isnt -1 then '&' else '?'
    for qp of this.queryParams
      if qp isnt 'url' and qp isnt 'refresh' and this.queryParams[qp]
        url += qp + '=' + this.queryParams[qp] + '&'
    res = API.http.puppeteer url, refresh
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
  try
    if Array.isArray lookup
      lookup = JSON.stringify lookup.sort()
    else if typeof lookup is 'object'
      lk = ''
      keys = _.keys lookup
      keys.sort()
      for k in keys
        lk += '_' + k + '_' + if typeof lookup[k] is 'object' then JSON.stringify(lookup[k]) else lookup[k]
      lookup = lk
    lookup = encodeURIComponent(lookup)
  catch
    return undefined
  return undefined if typeof lookup isnt 'string'
  return API.http._save(lookup, type, content) if content?
  API.http._colls[type] ?= new API.collection index: API.settings.es.index + "_cache", type: type
  try
    fnd = 'lookup.exact:"' + lookup + '"'
    if typeof refresh is 'number' and refresh isnt 0
      fnd += ' AND createdAt:>' + (Date.now() - refresh)
    res = API.http._colls[type].find fnd, true
    if res?._raw_result?.string?
      #API.log {msg:'Returning string result from cache', lookup:lookup, type:type}
      return res._raw_result.string
    else if res?._raw_result?.bool?
      #API.log {msg:'Returning object boolean result from cache', lookup:lookup, type:type}
      return res._raw_result.bool
    else if res?._raw_result?.number?
      #API.log {msg:'Returning object number result from cache', lookup:lookup, type:type}
      return res._raw_result.number
    else if res?._raw_result?.content?
      #API.log {msg:'Returning object content result from cache', lookup:lookup, type:type}
      return res.content
    else if res?._raw_result?.stringify
      try
        parsed = JSON.parse res._raw_result.stringify
        #API.log {msg:'Returning parsed stringified content result from cache', lookup:lookup, type:type}
        return parsed
  return undefined

API.http.resolve = (url,refresh=false) ->
  cached = if not refresh then API.http.cache(url, 'http_resolve') else false
  if cached
    return cached
  else
    try
      try
        resolved = API.use.crossref.resolve(url) if url.indexOf('10') is 0 or url.indexOf('doi.org/') isnt -1
      resolve = (url, callback) ->
        API.log 'Resolving ' + url
        # unfortunately this has to return the URL rather than false if it fails,
        # because some URLs are valid but blocked to our server, such as http://journals.sagepub.com/doi/pdf/10.1177/0037549715583150
        request.head url, {timeout:7000, jar:true, headers: {'User-Agent':'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36'}}, (err, res, body) ->
          if err and JSON.stringify(err).indexOf('TIMEDOUT') isnt -1
            API.log msg: 'http resolve timed out', url: url, error: err, level: 'warn'
            callback null, url
          else
            callback null, (if not res? or (res.statusCode? and res.statusCode > 399) then false else res.request.uri.href)
      aresolve = Meteor.wrapAsync resolve
      resolved = aresolve resolved ? url
      API.http.cache(url, 'http_resolve', resolved) if resolved?
      return resolved ? url
    catch
      return url

API.http.decode = (content) ->
  _decode = (content) ->
    # https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node
    translator = /&(nbsp|amp|quot|lt|gt);/g
    translate = {
      "nbsp":" ",
      "amp" : "&",
      "quot": "\"",
      "lt"  : "<",
      "gt"  : ">"
    }
    return content.replace(translator, ((match, entity) ->
      return translate[entity]
    )).replace(/&#(\d+);/gi, ((match, numStr) ->
      num = parseInt(numStr, 10)
      return String.fromCharCode(num)
    ))
  return _decode(content).replace(/\n/g,'')

API.http.post = (url, file, vars) ->
  # this has only been tested where file is a buffer
  _post = (url, file, vars, callback) ->
    conf = {url: url, formData: form}
    r = request.post url, (err, res, body) -> callback null, (if res? then res else err)
    if file? or (vars? and (typeof vars is 'string' or not _.isEmpty vars))
      form = r.form()
      if vars? and typeof vars isnt 'string' and not _.isEmpty vars
        for k of vars
          form.append k, vars[k]
      if file?
        fl = false
        try
          if (typeof file.on is 'function' and typeof file.read is 'function') or file instanceof Buffer
            fl = file # file is already a stream
          else if typeof file is 'string'
            try
              fl = fs.createReadStream file # file is a string which could be a local file pointer
            catch
              fl = new Buffer(file) # otherwise it is just a string, so try to make a Buffer out of it
          else if typeof file is 'object'
            fl = new Buffer(JSON.stringify(file)) # assume it is an object to be serialised and POSTed
        if fl
          opts = {}
          if typeof vars is 'string'
            opts.filename = vars
          else if vars? and typeof vars is 'object' and (vars.name? or vars.filename?)
            opts.filename = vars.filename ? vars.name
          form.append 'file', fl, (if not _.isEmpty(opts) then opts else undefined)
  _apost = Meteor.wrapAsync _post
  res = _apost url, file, vars
  return res

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
# phantom does not work any more, just leaving the code here in case useful for reference later
_phantom = (url,delay=1000,refresh=86400000,callback) ->
  if typeof refresh is 'function'
    callback = refresh
    refresh = 86400000
  if typeof delay is 'function'
    callback = delay
    delay = 1000
  return callback(null,'') if not url? or typeof url isnt 'string'
  if refresh isnt true and refresh isnt 0
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

#API.http.phantom = Meteor.wrapAsync(_phantom)


# switch phantom completely for puppeteer using chrome instead
# https://www.npmjs.com/package/puppeteer
# should be able to access full page content
# https://github.com/GoogleChrome/puppeteer/issues/331
# however phantom does not seem to be the cause of the OOM error that was seen
# that appears to be something to do with the lantern process, but only for certain jobs that were in the system at one point
# which may or may not have caused phantom errors - but was probably something within the job itself.
# update 12072018 - although phantom may not have directly caused the OOM in noddy, it 
# does appear to leave too many hanging processes, even though they should all get cleared. 
# This results in all the machine memory getting used up so then the noddy stack OOMs anyway.
# This may be combo of how they are called in different threads. So, switch to puppeteer anyway. 

# 31012018 found that a script running many oab request type processes did still cause OOM even with puppeteer
# so somewhere this call is still leaving hanging puppeteers, as it was doing with phantomjs. Changed 
# puppeteer startup settings as below, and next time it ran the ~3.5k processes without failing, 
# but still climb to about 2.5gb memory usage over seven hours or so. Only one puppeteer at a time 
# started up, and they all seemed to close as expected, but something somewhere is still stacking 
# up some memory. After the processes were all done, memory usage fell back, but still at about 1gb
# whereas without running that processing script the app only takes up a few hundred mb at idle. So, 
# it is not exactly a leak, but an excess remaining allocation. Need to investigate further.

# can also update my crawl / spider scripts using puppeteer
# https://github.com/GoogleChromeLabs/puppeteer-examples/blob/master/crawlsite.js

# puppeteer default meteor npm install should install chromium for itself to use, but it fails to find it
# so try adding chrome to the machine directly (which will have to be done for any cluster machines)
# wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 
# sudo sh -c 'echo "deb https://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
# sudo apt-get update
# sudo apt-get install google-chrome-stable
# and check that which google-chrome does give the path used below (could add a check of this, and output something if not found
# or even do the install? Could make this the necessary way to go for other things that include machine installations too
# they could have an install function which must run if the which command cannot find the expected executable
# then once the which command can find one, just use that
# TODO use some checks to see where the installed chrome/chromium is, if it is there
# if not, try to get it using browserFetcher https://github.com/GoogleChrome/puppeteer/blob/master/docs/api.md#class-browserfetcher
# tracking and re-using open chrome browsers appears to leave more hanging and use more memory than just opening and closing one every time
# tried with counters and also with counting the pages the browser thinks are open - not reliable enough, so go back to opening then closing every time
#_puppetEndpoint = false
#_puppetPages = 0
_puppeteer = (url,refresh=86400000,proxy,callback) ->
  if typeof refresh is 'function'
    callback = refresh
    refresh = 86400000
  if typeof proxy is 'function'
    callback = proxy
    proxy = undefined
  return callback(null,'') if not url? or typeof url isnt 'string'
  url = 'http://' + url if url.indexOf('http') is -1
  if refresh isnt true and refresh isnt 0
    cached = API.http.cache url, 'puppeteer', undefined, refresh
    return callback(null,cached) if cached?
  API.log 'starting puppeteer retrieval of ' + url
  try
    #browser = false
    #if _puppetEndpoint isnt false
    #  try browser = await puppeteer.connect({browserWSEndpoint:_puppetEndpoint})
    #if browser is false
    args = ['--no-sandbox', '--disable-setuid-sandbox']
    args.push('--proxy-server='+proxy) if proxy
    browser = await puppeteer.launch({args:args, ignoreHTTPSErrors:true, dumpio:false, timeout:12000, executablePath: '/usr/bin/google-chrome'})
    #_puppetEndpoint = browser.wsEndpoint()
    page = await browser.newPage()
    #_puppetPages += 1
    await page.goto(url, {timeout:12000})
    content = await page.evaluate(() => new XMLSerializer().serializeToString(document.doctype) + '\n' + document.documentElement.outerHTML)
    #_puppetPages -= 1
    #if _puppetPages is 0
    await browser.close()
    try
      API.http.cache(url, 'puppeteer', content) if typeof content is 'string' and content.length > 200
    return callback null, content
  catch
    try await browser.close()
    #_puppetEndpoint = false
    #_puppetPages = 0
    return callback null, ''

API.http.puppeteer = Meteor.wrapAsync(_puppeteer)



################################################################################

API.add 'http/puppeteer/test',
  get:
    roleRequired: (if API.settings.dev then undefined else 'root')
    action: () -> return API.http.puppeteer.test this.queryParams.verbose, this.queryParams.url, this.queryParams.find

API.http.puppeteer.test = (verbose,url='https://cottagelabs.com',find='cottage labs') ->
  console.log('Starting http test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    () ->
      rs = API.http.puppeteer(url)
      return typeof rs isnt 'number' and rs.toLowerCase().indexOf(find) isnt -1
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending http test') if API.settings.dev

  return result
