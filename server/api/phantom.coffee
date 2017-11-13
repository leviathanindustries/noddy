
import Future from 'fibers/future'
import phantom from 'phantom'
import fs from 'fs'

API.use ?= {}
API.phantom = {}

API.add 'phantom',
  get: () ->
    return
      statusCode: 200
      headers:
        'Content-Type': 'text/' + this.queryParams.format ? 'plain'
      body: API.phantom.get this.queryParams.url, this.queryParams.delay ? 1000


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
  ppath = if fs.existsSync('/usr/bin/phantomjs') then '/usr/bin/phantomjs' else '/usr/local/bin/phantomjs'
  phantom.create(['--ignore-ssl-errors=true','--load-images=false','--cookies-file=./cookies.txt'],{phantomPath:ppath})
    .then((ph) ->
      _ph = ph
      API.log('creating page')
      return ph.createPage()
    )
    .then((page) ->
      _page = page
      page.setting('resourceTimeout',3000)
      page.setting('loadImages',false)
      page.setting('userAgent','Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36')
      API.log('retrieving page ' + url)
      page.onResourceReceived = (resource) ->
        if url is resource.url and resource.redirectURL
          _redirect = resource.redirectURL
      return page.open(url)
    )
    .then((status) ->
      if _redirect
        API.log('redirecting to ' + _redirect)
        _page.close()
        _ph.exit()
        _phantom(_redirect,delay,callback)
      else
        API.log('retrieving content');
        future = new Future()
        setTimeout (() -> future.return()), delay
        future.wait()
        return _page.property('content')
    )
    .then((content) ->
      API.log(content.length)
      if content.length < 200 and delay <= 11000
        delay += 5000
        _page.close()
        _ph.exit()
        redirector = undefined
        API.log('trying again with delay ' + delay)
        _phantom(url,delay,callback)
      else
        API.log('got content')
        _page.close()
        _ph.exit()
        _redirect = undefined
        return callback(null,content)
    )
    .catch((error) ->
      console.log error
      API.log({msg:'phantom errored',error:error})
      _page.close()
      _ph.exit()
      _redirect = undefined
      return callback(null,'')
    )

API.phantom.get = Meteor.wrapAsync(_phantom)








