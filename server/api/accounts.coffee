import moment from 'moment'
import Future from 'fibers/future'
import { Random } from 'meteor/random'
import crypto from 'crypto'

# Users is exposed as global in case required, but should not be used - this accounts module exists to interact with Users
@Users = new API.collection type: "users", history: true
@Tokens = new API.collection "token"

API.accounts = {}

API.add 'accounts',
  get:
    authOptional: true
    action: () -> return if API.accounts.auth('root', this.user) then Users.search this.queryParams else count: Users.count()
  post:
    roleRequired: 'root'
    action: () ->
      return Users.search this.bodyParams

API.add 'accounts/xsrf', post: authRequired: true, action: () -> return API.accounts.xsrf this.userId

API.add 'accounts/token',
  get: () ->
    this.queryParams.action ?= 'login'
    return API.accounts.token this.queryParams
  post: () ->
    this.bodyParams.action ?= 'login'
    return API.accounts.token this.bodyParams

API.add 'accounts/login',
  post:
    authOptional: true # it is possible to get a noddy login POST from same domain that will contain an already valid cookie, resulting in already having valid user
    action: () ->
      future = new Future();
      setTimeout (() -> future.return()), 100
      future.wait()
      return API.accounts.login this.bodyParams, this.user, this.request

API.add 'accounts/logout',
  post: authRequired: true, action: () -> API.accounts.logout this.userId

API.add 'accounts/logout/:id',
  post: roleRequired: 'root', action: () -> API.accounts.logout this.urlParams.id

API.add 'accounts/:id',
  get:
    authRequired: true
    action: () -> return API.accounts.details this.urlParams.id, this.user
  post:
    authRequired: true
    action: () ->
      return if API.settings.accounts?.xsrf and not API.accounts.xsrf(this.userId, this.queryParams.xsrf) then 401 else API.accounts.update this.urlParams.id, this.request.body, this.user
  # TODO could add PUT as complete overwrite, but then who should have permissions to do that?
  delete:
    authRequired: true
    action: () ->
      return if API.settings.accounts?.xsrf and not API.accounts.xsrf(this.userId, this.queryParams.xsrf) then 401 else API.accounts.remove this.urlParams.id, this.user, this.queryParams.service

API.add 'accounts/:id/auth/:grouproles',
  get: () -> return auth: API.accounts.auth this.urlParams.grouproles.split(','), this.urlParams.id

API.add 'accounts/:id/roles/:grouprole',
  post:
    authRequired: true
    action: () ->
      return 401 if API.settings.accounts?.xsrf and not API.accounts.xsrf this.userId, this.queryParams.xsrf?
      added = API.accounts.addrole this.urlParams.id, this.urlParams.grouprole, this.user
      return if added then true else 403
  delete:
    authRequired: true
    action: () ->
      return 401 if API.settings.accounts?.xsrf and not API.accounts.xsrf this.userId, this.queryParams.xsrf?
      removed = API.accounts.removerole this.urlParams.id, this.urlParams.grouprole, this.user
      return if removed then true else 403



API.accounts.token = (tok, send=true) ->
  settings = API.settings.service?[tok.service]?.accounts ? API.settings.accounts
  settings.cookie ?= API.settings.accounts?.cookie
  _token = Random.hexString 7
  console.log _token if API.settings.log?.level is 'debug'
  tok.token = API.accounts.hash _token
  _hash = Random.hexString 40
  tok.hash = API.accounts.hash _hash
  tok.url ?= settings.url # TODO is it worth checking validity of incoming urls?
  tok.url += '#' + tok.hash if tok.url?
  tok.timeout = Date.now() + (tok.timeout ? settings.timeout ? 30) * 60 * 1000 # convert to ms from now
  Tokens.insert tok
  tok.hash = _hash
  tok.token = _token

  if send and tok.email
    snd = from: settings.from, to: tok.email, service: tok.service
    if settings.template
      snd.template = filename: settings.template, service: tok.service
      snd.vars = useremail: tok.email, loginurl: tok.url, logincode: tok.token
    else
      snd.subject = settings.subject
      snd.text ?= settings.text
      snd.html ?= settings.html
      re = new RegExp '\{\{LOGINCODE\}\}', 'g'
      ure = new RegExp '\{\{LOGINURL\}\}', 'g'
      tre = new RegExp '\{\{TIMEOUT\}\}', 'g'
      snd.text = snd.text.replace(re, tok.token).replace(ure,tok.url).replace(tre,(tok.timeout ? settings.timeout ? 30)) if snd.text
      snd.html = snd.html.replace(re, tok.token).replace(ure,tok.url).replace(tre,(tok.timeout ? settings.timeout ? 30)) if snd.html
    try
      # allows things to continue if e.g. on dev and email not configured
      sent = API.mail.send snd
      future = new Future()
      setTimeout (() -> future.return()), 333
      future.wait()
      return mid: sent?.data?.id ? true
    catch
      return false
  else
    return tok

API.accounts.oauth = (creds,service,fingerprint) ->
  # https://developers.google.com/identity/protocols/OAuth2UserAgent#validatetoken
  API.log "API login for oauth"
  user = undefined
  sets = {}
  if creds.service is 'google'
    validate = HTTP.call 'POST', 'https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=' + creds.access_token
    cid = API.settings.service[service]?.GOOGLE_OAUTH_CLIENT_ID ? API.settings.GOOGLE_OAUTH_CLIENT_ID
    if validate.data?.aud is cid
      ret = HTTP.call 'GET', 'https://www.googleapis.com/oauth2/v2/userinfo?access_token=' + creds.access_token
      user = API.accounts.retrieve ret.data.email
      user = API.accounts.create(ret.data.email, fingerprint) if not user?
      sets.google = {id:info.id} if not user.google?
      sets['profile.name'] = info.name if not user.profile.name and info.name
      sets['profile.firstname'] = info.given_name if not user.profile.firstname and info.given_name
      sets['profile.lastname'] = info.family_name if not user.profile.lastname and info.family_name
      sets['profile.avatar'] = info.picture if not user.profile.avatar and info.picture
  else if creds.service is 'facebook'
    fappid = API.settings.service[service]?.FACEBOOK_APP_ID ? API.settings.FACEBOOK_APP_ID
    fappsec = API.settings.service[service]?.FACEBOOK_APP_SECRET ? API.settings.FACEBOOK_APP_SECRET
    adr = 'https://graph.facebook.com/debug_token?input_token=' + creds.access_token + '&access_token=' + fappid + '|' + fappsec
    validate = HTTP.call 'GET', adr
    if validate.data?.data?.app_id is fappid
      ret = HTTP.call 'GET', 'https://graph.facebook.com/v2.10/' + validate.data.data.user_id + '?access_token=' + creds.access_token + '&fields=email,name,first_name,last_name,picture.width(400).height(400)'
      user = API.accounts.retrieve ret.data.email
      user = API.accounts.create(ret.data.email, fingerprint) if not user?
      sets.facebook = {id:validate.data.data.user_id} if not user.facebook?
      sets['profile.name'] = info.name if not user.profile.name? and info.name
      sets['profile.firstname'] = info.first_name if not user.profile.firstname and info.first_name
      sets['profile.lastname'] = info.last_name if not user.profile.lastname and info.last_name
      sets['profile.avatar'] = info.picture.data.url if not user.profile.avatar and info.picture?.data?.url
  Users.update user._id, sets if JSON.stringify(sets) isnt '{}'
  return user

# login requires params.hash OR params.email and params.token OR params.timestamp and params.resume OR user
# should provide url and service name too, and device fingerprint will be saved if provided
API.accounts.login = (params, user, request) ->
  Tokens.remove 'timeout:<' + Date.now() # get rid of old tokens
  token
  user = API.accounts.retrieve(user) if typeof user is 'string'
  user = API.accounts.oauth(request.body.oauth,params.service,params.fingerprint) if request?.body?.oauth?
  if not user
    if params.resume and params.timestamp
      token = Tokens.find resume: API.accounts.hash(params.resume), timestamp: params.timestamp, action: 'resume'
      API.log 'Found resume token with resume and timestamp' if token
    if not token and params.hash
      token = Tokens.find hash: API.accounts.hash(params.hash), action: 'login'
      API.log 'Found login token with hash' if token
    if not token and params.email and params.token
      token = Tokens.find email: params.email, token: API.accounts.hash(params.token), action: 'login'
      API.log 'Found login token with email and token' if token
    if token
      params.email ?= token.email
      Tokens.remove token._id # token can only be used once
      user = API.accounts.retrieve params.email
      API.log 'Found user for login with token' if user
      if not user #still no user, create a new one - unless service requires registration, in which case do what?
        user = API.accounts.create params.email, params.fingerprint
        API.log 'Created user ' + user._id + ' at login'

  settings = API.settings.service?[params.service]?.accounts ? API.settings.accounts
  settings.cookie ?= API.settings.accounts?.cookie

  if params.service and user?.service?[params.service]?.removed is true
    API.log 'An already removed user ' + user._id + ' tried to access ' + params.service
    return if request then 401 else false
  else if user
    API.log msg: 'Responding with confirmation of login for user', params: params, level: 'debug'
    API.accounts.fingerprint(user, params.fingerprint, 'login') if params.fingerprint and not user.devices?[API.accounts.hash(params.fingerprint)]?
    API.accounts.addrole(user, params.service+'.user') if params.service and not user.roles?[params.service]?
    if request and API.settings.log.root and 'root' in user.roles?.__global_roles__?
      API.log msg: 'Root login', notify: subject: 'root user login from ' + request.headers['x-real-ip'], text: 'root user logged in\n\n' + token?.url ? params.url + '\n\n' + request.headers['x-real-ip'] + '\n\n' + request.headers['x-forwarded-for'] + '\n\n'

    _rs = Random.hexString 30
    nt = uid: user._id, action: 'resume', resume: API.accounts.hash(_rs), timestamp: Date.now(), timeout: Date.now() + (settings.cookie?.timeout ? 259200) * 60 * 1000
    nt.fingerprint = API.accounts.hash(params.fingerprint) if params.fingerprint
    nt.timeout_date = moment(nt.timeout, "x").format "YYYY-MM-DD HHmm"
    Tokens.insert nt
    services = {}
    services[s] = _.omit(user.service[s], 'private') for s of user.service
    return
      apikey: user.api.keys[0].key
      account:
        email: params.email
        _id: user._id
        username: user.username ? user.emails[0].address
        profile: user.profile
        roles: user.roles
        service: services
      settings:
        timestamp: nt.timestamp
        resume: _rs
        domain: token?.domain ? settings?.domain # TODO should it be allowed to be passed in to token, or only from config?
        expires: settings?.cookie?.expires ? 180
        httponly: settings?.cookie?.httponly ? false
        secure: settings?.cookie?.secure ? true
  else
    API.log msg: 'User unauthorised', params: params, level: 'debug'
    return if request then 401 else false

API.accounts.logout = (user) ->
  user = user._id if typeof user is 'object'
  Tokens.remove uid: user, action: 'resume'
  return true

API.accounts.auth = (grl, user, cascade=true) ->
  user = API.accounts.retrieve(user) if typeof user is 'string'
  return false if not user
  grl = [grl] if typeof grl is 'string'
  for g in grl
    [group, role] = g.split '.'
    if not role?
      role = group
      group = '__global_roles__'

    return 'root' if group is user._id # any user is effectively root on their own group - which matches their user ID
    return false if not user.roles? # if no roles can't have any auth, except on own group (above)
    if 'root' in user.roles.__global_roles__ # root has access to everything
      API.log 'user ' + user._id + ' has role root'
      return 'root'

    if user.roles[group]?.indexOf role isnt -1
      API.log 'user ' + user._id + ' has role ' + g
      return role

    # check for higher auth in cascading roles for group - TODO allow cascade on global?
    if cascade
      cascade = ['root', 'service', 'super', 'owner', 'admin', 'auth', 'publish', 'edit', 'read', 'user', 'info', 'public'] if cascade is true
      ri = cascade.indexOf role
      if ri isnt -1
        cascs = cascade.splice 0, ri
        for r in cascs
          rl = cascs[r]
          if rl in user.roles[group]?
            API.log 'user ' + user._id + ' has cascaded role ' + group + '.' + rl + ' overriding ' + g
            return rl

  API.log 'user ' + user._id + ' does not have role ' + grl
  return false

API.accounts.create = (email, fingerprint) ->
  return false if (JSON.stringify(email).indexOf('<script') isnt -1) or (email.indexOf('@') is -1) # ignore if looks dodgy
  password = Random.hexString 30
  apikey = Random.hexString 30
  # can have a username key, which must be handled to ensure uniqueness, but should it default to anything?
  u =
    email: email
    password: API.accounts.hash(password)
    profile: {} # profile data that the user can edit will go here
    devices: {} # user devices associated by device fingerprint can be stored here
    service: {} # services identified by service name, which can be changed by those in control of the service. Viewable by user unless in private key, but only editable by user if in profile key
    api: keys: [{ key: apikey, hash: API.accounts.hash(apikey), name: 'default' }]
    emails: [{ address: email, verified: true }]
  first = Users.count() is 0
  u._id = "0" if first
  u.roles = if first then __global_roles__: ['root'] else {}
  u.devices[API.accounts.hash(fingerprint)] = {action: 'create', createdAt: Date.now()} if fingerprint
  u._id = Users.insert u
  API.log "Created user " + u._id
  return u # API.accounts.retrieve u._id is it worth doing a retrieve, or just pass back what has been calculated?

API.accounts.retrieve = (val) ->
  u
  srch
  if typeof val is 'object'
    if val.apikey?
      # a convenience for passing in apikey searches - these must be separate and specified, unlike id / email searches, otherwise putting an id as apikey would return a user object
      srch = {'api.keys.hash.exact': API.accounts.hash(val.apikey)}
    else
      srch = ''
      for k in val
        srch += (srch.length ? ' AND ') + k + ':' + val[k]
  else if typeof val is 'string' and val.indexOf(' ') isnt -1
    srch = val
  else
    u = Users.get val # try ID get first, because will return immediately after insert whereas search will not
    srch = if u? then ' get ID' else '_id:"' + val + '" OR username.exact:"' + val + '" OR emails.address.exact:"' + val + '"'
  u ?= Users.find srch
  if u
    API.log msg: 'Retrieved account for val ' + JSON.stringify(val) + ' with ' + JSON.stringify(srch), retrieved: u._id if u
    return u
  else
    return undefined

# return user account with everything if root, otherwise with only what user can see if user, or else only what service can see if service
API.accounts.details = (user, uacc) ->
  if typeof user is 'string'
    user = if typeof uacc is 'object' and uacc._id is user then uacc else API.accounts.retrieve(user)
  if typeof uacc is 'string'
    uacc = if typeof user is 'object' and user._id is uacc then user else API.accounts.retrieve(uacc)
  return false if not user?
  if not uacc? or API.accounts.auth 'root', uacc
    # we return everything - would be a pretty pointless use of this method, but possible
  else if (user._id is uacc._id) or API.accounts.auth user._id + '.read', uacc
    user = _.pick user, '_id','profile','username','emails','api','roles','service'
    if user.service?
      services = {}
      services[s] = _.omit(user.service[s], 'private') for s of user.service
      user.service = services
  else if user.service? and uacc?
    for s of user.service
      delete user.service[s] if not API.accounts.auth s + '.service', uacc
    user = _.pick user, '_id','profile','username','emails','roles','service'
  return user

# user can update profile and any profile part of any service (their username, emails, api keys, devices have to be managed directly)
# srevice can update any service info
API.accounts.update = (user, update, uacc) ->
  API.log msg: 'Updating user account details', user: user, uacc: uacc, update: update, level: 'info'
  return false if JSON.stringify(update).indexOf('<script') isnt -1
  user = user._id if typeof user is 'object'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'

  if uacc and not API.accounts.auth 'root', uacc
    acceptable = []
    if (uacc._id is user) or API.accounts.auth user+'.edit', uacc
      for p of update
        if p is 'profile' or p.indexOf('profile') is 0 or (p.indexOf('service.') is 0 and p.split('.')[2] is 'profile')
          acceptable.push p
    else
      for p of update
        if p.indexOf('service.') is 0 and API.accounts.auth p.split('.')[1]+'.service', uacc
          acceptable.push p
    update = _.pick update, acceptable # annoyingly, passing the function to pick instead of key list does not seem to be working

  if not _.isEmpty(update)
    API.log msg: 'User has rights to update ' + _.keys(update), update: update, level: 'info'
    Users.update user, update
    return true
  else
    API.log msg: 'User did not have rights to update the provided content'
    return false

API.accounts.addrole = (user, grl, uacc) ->
  user = API.accounts.retrieve(user) if typeof user is 'string'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'
  [group, role] = grl.split '.'
  if not role?
    role = group
    group = '__global_roles__'

  k = 'roles'
  if user.roles[group]?
    k += '.group.' + user.roles[group].length
  else
    nr = [role]
    role = {}
    role[group] = nr
  set = {}
  set[k] = role

  if API.settings.service?[group]?
    if not user.service
      set.service = {}
      set.service[group] = profile: {}, private: {}
    else if not user.service[group]?
      set['service.' + group] = profile: {}, private: {}

  if role is 'public' or not uacc? or API.accounts.auth group + '.auth', uacc
    Users.update user._id, set
    return true
  else
    return false

API.accounts.removerole = (user, grl, uacc) ->
  user = API.accounts.retrieve(user) if typeof user is 'string'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'
  [group, role] = grl.split '.'
  if not role?
    role = group
    group = '__global_roles__'

  if role in user.roles?[group]
    if role is 'public' or not uacc? or API.accounts.auth group + '.auth', uacc
      user.roles[group].splice user.roles[group].indexOf(role), 1
      set = {}
      set['roles.' + group] = user.roles[group]
      Users.update user._id, set
      return true
    else
      return false
  else
    return true

API.accounts.remove = (user, service, uacc) ->
  user = API.accounts.retrieve(user) if typeof user is 'string'
  uacc = API.accounts.retrieve(uacc) if typeof uacc is 'string'
  if not uacc? or user._id is uacc._id or API.accounts.auth 'root', uacc
    if service
      Users.update user._id, 'service.'+service+ '.removed': true
    else
      Users.remove user._id
    return true
  else if uacc? and service and API.accounts.auth service+'.service', uacc
    if _.keys(user.service).length is 1 and user.service[service]?
      Users.remove user._id
    else
      upd = {}
      upd['service.'+service] = {removed:true}
      Users.update user._id, upd
    return true
  else
    return false

# this should be developed further or in combo with a devices action, see below comments
API.accounts.fingerprint = (uid, fingerprint, action) ->
  uid = API.accounts.retrieve(uid) if typeof uid is 'string'
  dv = {}
  dv['devices.'+API.accounts.hash(fingerprint)] = action:action, createdAt: Date.now()
  Users.update(uid._id, dv) if not uid.devices?[fingerprint]?

# TODO should have a function to add/remove emails to an account (no accounts should share emails)
# and a function to change/get/create new API key, as well as one to set/change username (which must also be unique)
# and one to manage the devices (could register a device as one to receive tokens on, when logged in on that device)
# this could also manage logins across devices, perhaps

API.accounts.hash = (token) ->
  token = token.toString() if typeof token is 'number'
  hash = crypto.createHash 'sha256'
  hash.update token
  return hash.digest 'base64'

API.accounts.xsrf = (uid, xsrf) ->
  uid = uid._id if typeof uid is 'object'
  if xsrf isnt undefined
    exists = if xsrf is false then false else Tokens.find hash: API.accounts.hash(xsrf), action: 'xsrf', uid: uid
    # Tokens.remove exists._id if exists? # for now, leave xsrf tokens alive for re-use within timeout window (4 hours) - but could make them one-time use
    return exists
  else
    return xsrf: API.accounts.token(action: 'xsrf', uid: uid, timeout: 240, false).hash
