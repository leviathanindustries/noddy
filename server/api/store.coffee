import fs from 'fs'
import { Random } from 'meteor/random'
import request from 'request'
import formdata from 'form-data'
import Future from 'fibers/future'

# NOTE tested with Meteor HTTP GET files, it corrupts them. So does using request in any way other than async streaming
# hence the odd stuff below using request to pipe, then waiting to check on the stream being done, then doing something,
# instead of jsut wrapping in fiber or async etc

store = new API.collection 'store' # would history be useful on this? could know when files were created and deleted and by whom...

API.store = {}

if not API.settings.store?
  console.log 'STORE WARNING - THERE ARE NO STORE PARAMS SET'
else if not API.settings.store.folder
  console.log 'STORE WARNING - THERE IS NO STORE FOLDER SET (which does not matter for cluster machines, but probably should be there anyway)'
else if not fs.existsSync API.settings.store.folder
  console.log 'STORE WARNING - STORE FOLDER DOES NOT EXIST (does not matter for cluster machines but is necessary for main machine, where it must be manually created)'
API.settings.store?.local ?= API.settings.store?.api

API.add 'store', get: () -> return if this.queryParams?.token? then Tokens.get(this.queryParams.token)? else API.store.list()

# NOTE use nginx config to ensure these routes only get hit on the machine that holds the storage folder
# anything stored public should be accessed via an nginx route on a URL that just serves the public storage folder
# anything stored secure must be accessed on the /store/... API path, and auth for it will be checked

_root = 'store'
for r in [0,1,2,3,4]
  _root += '/:r' + r
  API.add _root,
    get:
      authOptional: true
      action: () ->
        path = this.request.url.replace('/api','').replace('/store','').split('?')[0].split('#')[0]
        if API.settings.store.url and path.indexOf(API.settings.store.local) isnt 0 and not store.get(path.replace(/\//g,'_'))?.secure
          # have nginx configured to serve the public URL
          return {statusCode: 302, headers: { Location: API.settings.store.url + path }, body: 'Location: ' + API.settings.store.url + path }
        else
          res = API.store.retrieve path, this.user, this.queryParams.token
          if res is false
            API.log msg: 'User unauthorised to access store route', url: path, uid: this.userId, method: 'GET', status: 401
            return 401
          else if res is undefined
            API.log msg: 'User tried to access unavailable store route', url: path, uid: this.userId, method: 'GET', status: 404
            return 404
          else if res.byteLength?
            API.log msg: 'User accessed store route (return file)', url: path, uid: this.userId, method: 'GET', status: 200
            this.response.writeHead 200
            this.response.end res
            this.done()
          else
            try
              API.log msg: 'User accessed store route (return JSON)', url: path, uid: this.userId, method: 'GET', status: 200
              return res
            catch
              API.log msg: 'User tried to access store route error', url: path, uid: this.userId, method: 'GET', status: 400
              return 400
    put:
      authOptional: true
      action: () ->
        API.log msg: 'User sending content to store route', url: path, uid: this.userId
        return API.store.create(this.request.url.replace('/api','').replace('/store','').split('?')[0].split('#')[0], this.user, this.queryParams.token, undefined, this.queryParams.secure ? this.bodyParams.secure) ? 401
    post:
      authOptional: true
      action: () ->
        API.log msg: 'User sending content to store route'
        return API.store.create(this.request.url.replace('/api','').replace('/store','').split('?')[0].split('#')[0], this.user, this.queryParams.token, (if not _.isEmpty(this.request.body?) then this.request.body else this.request.files), this.queryParams.secure ? this.bodyParams.secure) ? 401
    delete:
      authOptional: true
      action: () ->
        res = API.store.delete this.request.url.replace('/api','').replace('/store','').split('?')[0].split('#')[0], this.user, this.queryParams.token
        return if res is true then true else (if res is false then 401 else 404)



API.store.token = (path, email, action=['GET'], timeout=API.settings.store.timeout ? 1440) ->
  # other code can use this to get a token to allow one store action for an otherwise unauthorised user
  # token can be checked if path + #token matches token.url, email matches token.email, action matches token.fingerprint
  # action can only be a string like 'GET' 'POST' 'PUT' 'DELETE' or a list containing a subset of those
  # timeout 1440 minutes = 1 day. 2880 is 2 days. 10080 is a week. 525600 is about a year.
  return API.accounts.token({email: email, url: path, service: 'store', fingerprint: action, timeout: timeout}, false).token

API.store.allowed = (path, user, token, action='GET', security=store.get(path.replace(/\//g,'_'))?.secure, listing) ->
  if token
    Tokens.remove 'timeout:<' + Date.now()
    if token = Tokens.find({token: API.accounts.hash(token)})
      Tokens.remove token._id if not listing
      token.fingerprint = [token.fingerprint] if typeof token.fingerprint is 'string'
      return token.path is 'LOCAL' or (path.indexOf(token.url) is 0 and (not token.fingerprint or action in token.fingerprint))
    else
      return false
  else if security
    # can be true to indicate auth required, or a role string or object to indicate a role check, or an API. fn name to call
    if typeof security is 'boolean'
      return user?
    else if typeof security is string and security.indexOf('API.') is 0
      try
        fn = API[p] for p in security.replace('API.','').split('.')
        return fn path, action, user
      catch
        return false
    else if typeof security is 'string' or typeof security is 'object' and JSON.stringify(security).indexOf('[') is 0
      return API.accounts.auth security, user
    else if typeof security is 'object' and security[action]?
      return API.store.allowed path, user, token, action, security[action]
    else
      return false
  else if user?
    return true # could have a different default allowance - this allows anyone with an account to upload or delete, anyone at all to view
  else if action is 'GET'
    return true
  else
    return false

API.store.exists = (path) -> return store.get(path.replace(/\//g,'_'))? or fs.existsSync(API.settings.store.folder + path) or fs.existsSync(API.settings.store.secure + path)

API.store.list = (path=API.settings.store.folder, user, token) ->
  listing = []
  for l in fs.readdirSync path
    pt = path + '/' + l
    if fs.lstatSync(pt).isDirectory()
      rs = {}
      rs[l] = API.store.list pt, user, token
      if not (_.isEmpty(rs[l]) and not API.store.allowed pt, user, token, 'GET', undefined, true)
        listing.push rs
    else if not store.get(pt)?.secure or API.store.allowed pt, user, token, 'GET', undefined, true
      listing.push l

  return listing
  # check the user has permission to get listing on the current path, then recurse into it
  # for everything in it, check the permission again. If not allowed, do not show
  # but if allowd something further down a path, do show a higher folder, to get to it

API.store.create = (path, user, token, content, secure=false) ->
  if API.settings.store.local and not fs.existsSync API.settings.store.folder
    API.log msg: 'Redirecting store create request to storage server', method: 'API.store.create'
    token = API.store.token('LOCAL') if not token? and not user?
    try
      if (typeof content is 'object' or typeof content is 'string') and JSON.stringify(content)? # just to see if we can
        ret = HTTP.call('POST', API.settings.store.local + '/store' + path + '?token=' + token + '&apikey=' + user?.api.keys[0].key, content)
        API.log msg: 'Store POSTed JSON-able data to storage server, and returning received data', method: 'API.store.create'
        return ret.data
    catch
      try
        form = new formdata()
        form.append('secure', secure) if secure
        form.append 'file', content # TODO check does this work if content is string or buffer or object or stream?
        form.getLength (err,length) ->
          r = request.post API.settings.store.local + '/store' + path + '?token=' + token + '&apikey=' + user?.api.keys[0].key, { headers: { 'content-length': length } }
          r._form = form
        API.log msg: 'Store POSTed file data to storage server, and returning received response', method: 'API.store.create'
        return true
      catch
        return false
  else if API.store.allowed path, user, token, 'POST'
    API.log msg: 'Store handling create request on storage server for authorised user', uid: user?._id, method: 'API.store.create'
    # TODO should prob add a disk check and alert if it is too high
    while fs.existsSync path
      path = if path.indexOf('.') isnt -1 then path.split('.').splice(-1,0,Random.hexString(3)).join('.') else path + '-' + Random.hexString(3)
    res = _id:path.replace(/\//g,'_'), path: path, secure: secure, uid: user?._id, token: token
    res.url = (if res.secure or not API.settings.store.url then API.settings.store.api else API.settings.store.url) + path
    pt = if secure then API.settings.store.secure else API.settings.store.folder
    ipt = pt
    for p of parts = path.split('/')
      ipt += '/' + parts[p] if parts[p].length
      fs.mkdirSync(ipt) if parts.length > 1 and parseInt(p) isnt parts.length-1 and not fs.existsSync(ipt)
    path = pt + path
    return false if path.indexOf('../') isnt -1 # naughty catcher
    if not content? and API.store.allowed path, user, token, 'PUT'
      fs.mkdirSync path
    else if typeof content is 'string' and content.indexOf('http') is 0
      try
        request.get(content).pipe fs.createWriteStream path
        API.log msg: 'Store retrieving content for create from URL ' + content, method: 'API.store.create'
      catch
        API.log msg: 'Store failed to retrieve content for create from URL ' + content, method: 'API.store.create', level: 'error'
        return false
    else if typeof content is 'object' and content.length > 0 and content[0].filename?
      API.log msg: 'Store processing file upload content for create', method: 'API.store.create'
      try
        if content.length > 1
          fs.mkdirSync path
          res.files = []
        for f of content
          fn = if content.length is 1 then path else path + '/' + content[f].filename
          if f isnt '0'
            pr = JSON.parse JSON.stringify(res)
            pr._id = fn.replace(/\//g,'_')
            pr.path = fn
            store.insert pr
          fs.writeFileSync fn, content[f].data
          res.files.push(content[f].filename) if content.length > 1
      catch
        API.log msg: 'Store failed to process provided file(s) for create', method: 'API.store.create', level: 'error'
        return false
    else
      try
        fs.writeFileSync path, content
        API.log msg: 'Store writing provided content for create', method: 'API.store.create'
      catch
        try
          converted = JSON.stringify content
          fs.writeFileSync path, converted
          API.log msg: 'Store writing stringified provided JSON content for create', method: 'API.store.create'
        catch
          API.log msg: 'Store failed to save provided content for create', method: 'API.store.create', level: 'error'
          return false
    store.insert res
    return res
  else
    API.log msg: 'Store refusing create request on storage server for user', uid: user?._id, method: 'API.store.create'
    return false

# if this returns a JSON list, it could be the content of the file that was a JSON list
# BUT it could also be the directory listing, if what was requested turned out to be a directory
API.store.retrieve = (path, user, token) ->
  if API.settings.store.local and not fs.existsSync API.settings.store.folder
    API.log msg: 'Redirecting store retrieve request to storage server', method: 'API.store.retrieve'
    token = API.store.token('LOCAL') if not token? and not user?
    try
      fn = '~/tmp.file'
      fs.unlinkSync fn
      str = fs.createWriteStream fn # TODO need to check that cluster docker machines will have somewhere to write
      done = false
      str.on 'close', () -> done = true
      request.get(API.settings.store.local + path + '?token=' + token + '&apikey=' + user?.api.keys[0].key).pipe str
      while not done
        future = new Future();
        setTimeout (() -> future.return()), 300
        future.wait()
      return fs.readFileSync fn
    catch
      return undefined # a 404 etc will result in an error from the http call, so return undefined to indicate that
  else if API.store.allowed path, user, token, 'GET'
    API.log msg: 'Store handling retrieve request on storage server for authorised user', uid: user?._id, method: 'API.store.retrieve'
    pt = if store.get path.replace(/\//g,'_')?.secure then API.settings.store.secure else API.settings.store.folder
    return false if path.indexOf('../') isnt -1 # naughty catcher
    if not fs.existsSync pt + path
      return undefined # indicates not found
    else if fs.lstatSync(pt + path).isDirectory()
      return API.store.list pt + path, user, token
    else
      # return file content - if stream is true and stream code is added, return a stream of the file instead
      return fs.readFileSync pt + path
  else
    API.log msg: 'Store refusing retrieve request on storage server for user', uid: user?._id, method: 'API.store.retrieve'
    return false

API.store.delete = (path, user, token) ->
  deleteFolderRecursive = (path) ->
    if fs.existsSync path
      fs.readdirSync(path).forEach (file,index) ->
        curPath = path + "/" + file
        if fs.lstatSync(curPath).isDirectory()
          deleteFolderRecursive curPath
        else
          fs.unlinkSync curPath
          store.remove curPath
      fs.rmdirSync path
      store.remove path

  details = store.get path.replace(/\//g,'_')
  if not details?
    API.log msg: 'Store refusing delete request for item that was not saved via store API', uid: user?._id, method: 'API.store.delete'
    return false # don't delete things that were not created by this API
  else if API.settings.store.local and not fs.existsSync API.settings.store.folder
    # we are not on the storage machine, send the delete to the actual API addr which nginx should configure to the right machine
    API.log msg: 'Redirecting store delete request to storage server', method: 'API.store.delete'
    token = API.store.token('LOCAL') if not token? and not user?
    u = API.settings.store.local + path + '?' + 'token=' + token + '&apikey=' + user?.api.keys[0].key
    try
      return HTTP.call('DELETE', u).data
    catch
      API.log msg: 'Redirection of store delete request to storage server failed', method: 'API.store.delete', level: 'error'
      return undefined # a 404 would throw an error, so we return undefined when not found
  else if fs.existsSync path = (if details.secure then API.settings.store.secure else API.settings.store.folder) + path
    return false if path.indexOf('../') isnt -1 # naughty catcher
    if API.store.allowed path, user, token, 'DELETE'
      if fs.lstatSync(path).isDirectory()
        deleteFolderRecursive path
        API.log msg: 'Store delete request recursively deleting folder on storage server for authorised user', method: 'API.store.delete', uid: user?._id
      else
        fs.unlinkSync path
        API.log msg: 'Store delete request deleting file on storage server for authorised user', method: 'API.store.delete', uid: user?._id
      store.remove path
      return true
    else
      API.log msg: 'Store refusing delete request storage server for user', method: 'API.store.delete', uid: user?._id
      return false
  else
    API.log msg: 'Store delete request doing nothing for request to content that does not appear to exist', method: 'API.store.delete', uid: user?._id
    return undefined #return undefined for not found
