

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
    action: () ->
      delete this.queryParams.apikey if this.queryParams.apikey?
      return if API.accounts.auth('root', this.user) then Users.search(if _.isEmpty(this.queryParams) then '*' else this.queryParams) else count: Users.count()
  post:
    roleRequired: 'root'
    action: () ->
      return Users.search(if _isEmpty(this.bodyParams) then '*' else this.bodyParams)

API.add 'accounts/xsrf', post: authRequired: true, action: () -> return API.accounts.xsrf this.userId

API.add 'accounts/cookie',
  get:
    authRequired: true
    action: () ->
      # for an authorised user, lookup some value that should match an existing token, and which
      # NOTE if this is used, the resume tokens would not match from different sites - the user would have logged in somewhere else... resume less often?
      if this.queryParams.cut and false
        lgd = API.accounts.login {}, this.user
        return
          statusCode: 200
          headers:
            'Content-Type': 'text/html'
          body: '<html><script src="/noddy.js"></script><script>noddy.loginSuccess(' + JSON.stringify(lgd) + ')</script></html>'
      else
        return

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
      Meteor.setTimeout (() -> future.return()), 100
      future.wait()
      return API.accounts.login this.bodyParams, this.user, this.request

API.add 'accounts/logout',
  post: authRequired: true, action: () -> API.accounts.logout this.userId

API.add 'accounts/forgot',
  get: () ->
    if this.queryParams.token and this.queryParams.id
      token = Tokens.get this.queryParams.token
      if token?
        Tokens.remove this.queryParams.token
        # reset the user password and send an email out with the new password
        # and prompt the user to change it to something else on the change password screen
        # note then that this could be the change password screen for more than one service - and emails could come from more than one service
        # pass that service info in somehow
      else
        return false
    else if this.queryParams.id or this.queryParams.email or this.queryParams.username
      user = if this.queryParams.id then Users.get(this.queryParams.id) else API.accounts.retrieve(this.queryParams.email ? this.queryParams.username)
      if user?
        # create an xsrf token (or any token that lasts some time)
        # send an email to the account, with a reset password link back to here including the user account ID and the token ID
        # note the email address to send from, and the URL site address to click on, may differ by service
        return true
      else
        return false
    else
      return false

API.add 'accounts/logout/:id',
  post: roleRequired: 'root', action: () -> API.accounts.logout this.urlParams.id

API.add 'accounts/:id',
  get:
    authRequired: true
    action: () -> return API.accounts.details this.urlParams.id, this.user
  post:
    authRequired: true
    action: () ->
      try
        st = JSON.stringify this.request.body
        return 401 if st.indexOf('<script') isnt -1 or st.replace(' (','(').indexOf('function(') isnt -1
      catch
        return 401
      return if API.settings.accounts?.xsrf and not API.accounts.xsrf(this.userId, this.queryParams.xsrf) then 401 else API.accounts.update this.urlParams.id, this.request.body, this.user
  # TODO could add PUT as complete overwrite, but then who should have permissions to do that?
  delete:
    authRequired: true
    action: () ->
      return if API.settings.accounts?.xsrf and not API.accounts.xsrf(this.userId, this.queryParams.xsrf) then 401 else API.accounts.remove this.urlParams.id, this.user, this.queryParams.service

API.add 'accounts/:id/password',
  post:
    authRequired: true
    action: () ->
      return API.accounts.password this.bodyParams.password, this.user, this.urlParams.id

API.add 'accounts/:id/apikey',
  post:
    authRequired: true
    action: () ->
      return API.accounts.apikey undefined, this.user, this.urlParams.id

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
  settings.timeout ?= 30
  _token = Random.hexString 7
  console.log _token if API.settings.log?.level is 'debug'
  tok.token = API.accounts.hash _token
  _hash = Random.hexString 40
  tok.hash = API.accounts.hash _hash
  tok.url ?= settings.url # TODO is it worth checking validity of incoming urls?
  tok.url += '#' + _hash if tok.url?
  tok.timeout = Date.now() + (tok.timeout ? settings.timeout) * 60 * 1000 # convert to ms from now
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
      snd.text = snd.text.replace(re, _token).replace(ure,tok.url).replace(tre,settings.timeout) if snd.text
      snd.html = snd.html.replace(re, _token).replace(ure,tok.url).replace(tre,settings.timeout) if snd.html
      if settings.timeout >= 60 and snd.text and snd.text.indexOf(settings.timeout + ' minutes') isnt -1
        rp = settings.timeout / 60
        rp += if rp > 1 then ' hours' else ' hour'
        snd.text = snd.text.replace(settings.timeout + ' minutes',rp)
        snd.html = snd.html.replace(settings.timeout + ' minutes',rp) if snd.html
    try
      # https://developers.google.com/gmail/markup/reference/one-click-action
      if ex = API.accounts.retrieve tok.email
        if false #ex.createdAt < Date.now() - 300000
          # if not a new account creation in the last 5 mins, try to add a gmail login action button
          # 7bit encoding is necessary to get the schema data for the inline gmail buttons to display properly
          # normal email quoted=printable encoding converts = to 3D= and breaks the schema data, whether done in json-ld or microdata
          # so this is only useful for login emails that are not too long or complex, as 7bit encoding only allows for max 1000 char lines
          # NOTE annoyingly this does not work with mailgun to set the encoding header, so this still does not work. May have to send full mime messages to mailgun, which is annoying
          # Requiring the email template to have a confirmaction var is not too useful either - when this is fixed, look at a different way to handle it
          #snd['h:Content-Transfer-Encoding'] = '7bit'
          #snd['headers'] = {'Content-Transfer-Encoding':'7bit'}
          #snd['encoding'] = '7bit' # use this to force my mail code to use a mailcomposer object directly with 7bit Content-Transfer-Encoding
          #snd.text ?= 'Login at ' + tok.url # this forces a multipart to get the transfer encodings onto
          # none of the attempts to pass options to mailcomposer worked, including using a mailcomposer object directly in the mail method
          # only remaining option would be to build the MIME directly, but just not worth the hassle right now for a simple convenience in gmail
          snd.smtp = true
          btn = '<br><br>
<script type="application/ld+json">
{
  "@context": "http://schema.org", 
  "@type": "EmailMessage",
  "potentialAction": { 
    "@type": "ConfirmAction",
    "name": "Login",
    "handler": {
      "@type": "HttpActionHandler",
      "url": "' + tok.url + '"
    }
  },
  "description": "Login to ' + tok.service + '"
}
</script>'
          if snd.vars
            snd.append = btn
          else if snd.html?
            snd.html += btn
    #try
    # allows things to continue if e.g. on dev and email not configured
    sent = API.mail.send snd
    future = new Future()
    Meteor.setTimeout (() -> future.return()), 333
    future.wait()
    return mid: sent?.data?.id ? (if typeof snd.to is 'string' then snd.to else JSON.stringify snd.to)
    #catch
    #  return false
  else
    return tok

API.accounts.oauth = (creds,service,fingerprint) ->
  # https://developers.google.com/identity/protocols/OAuth2UserAgent#validatetoken
  API.log "API login for oauth " + creds.service + ' on ' + service
  user = undefined
  sets = {}
  try
    if creds.service is 'google'
      validate = HTTP.call 'POST', 'https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=' + creds.access_token
      cid = API.settings.service[service]?.google?.oauth?.client?.id ? API.settings.use?.google?.oauth?.client?.id
      if validate.data?.aud is cid
        ret = HTTP.call 'GET', 'https://www.googleapis.com/oauth2/v2/userinfo?access_token=' + creds.access_token
        user = API.accounts.retrieve ret.data.email
        user = API.accounts.create(ret.data.email, fingerprint) if not user?
        sets.google = {id:ret.data.id} if not user.google?
        sets['profile.name'] = ret.data.name if not user.profile.name and ret.data.name
        sets['profile.firstname'] = ret.data.given_name if not user.profile.firstname and ret.data.given_name
        sets['profile.lastname'] = ret.data.family_name if not user.profile.lastname and ret.data.family_name
        sets['profile.avatar'] = ret.data.picture if not user.profile.avatar and ret.data.picture
    else if creds.service is 'facebook'
      fappid = API.settings.service[service]?.facebook?.oauth?.app?.id ? API.settings.use?.facebook?.oauth?.app?.id
      fappsec = API.settings.service[service]?.facebook?.oauth?.app?.secret ? API.settings.use?.facebook?.oauth?.app?.secret
      adr = 'https://graph.facebook.com/debug_token?input_token=' + creds.access_token + '&access_token=' + fappid + '|' + fappsec
      validate = HTTP.call 'GET', adr
      if validate.data?.data?.app_id is fappid
        ret = HTTP.call 'GET', 'https://graph.facebook.com/v2.10/' + validate.data.data.user_id + '?access_token=' + creds.access_token + '&fields=email,name,first_name,last_name,picture.width(400).height(400)'
        user = API.accounts.retrieve ret.data.email
        user = API.accounts.create(ret.data.email, fingerprint) if not user?
        sets.facebook = {id:validate.data.data.user_id} if not user.facebook?
        sets['profile.name'] = ret.data.name if not user.profile.name? and ret.data.name
        sets['profile.firstname'] = ret.data.first_name if not user.profile.firstname and ret.data.first_name
        sets['profile.lastname'] = ret.data.last_name if not user.profile.lastname and ret.data.last_name
        sets['profile.avatar'] = ret.data.picture.data.url if not user.profile.avatar and ret.data.picture?.data?.url
    API.log('User ' + user._id + ' found by oauth login') if user?
  catch err
    API.log msg: 'Oauth login failed', err: err
  Users.update(user._id, sets) if JSON.stringify(sets) isnt '{}'
  return user

# login requires params.hash OR params.email and params.token OR params.timestamp and params.resume OR user
# should provide url and service name too, and device fingerprint will be saved if provided
API.accounts.login = (params, user, request) ->
  Tokens.remove 'timeout:<' + Date.now() # get rid of old tokens
  token
  user = API.accounts.retrieve(user) if typeof user is 'string'
  user = API.accounts.oauth(request.body.oauth,params.service,params.fingerprint) if request?.body?.oauth?
  if params?.password? and (params.username? or params.email?)
    user = API.accounts.retrieve({password:params.password})
    user = undefined if (params.email? and user.email isnt params.email and user.emails[0].address isnt params.email) or (user.username isnt params.username)
  if params.apikey? and params.email?
    user = API.accounts.retrieve({apikey:params.apikey})
    try
      user = undefined if user? and (user.email ? user.emails[0].address) isnt params.email
    catch
      user = undefined
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
      user = API.accounts.retrieve params.email
      API.log 'Found user for login with token' if user
      if not user #still no user, create a new one - unless service requires registration, in which case do what?
        user = API.accounts.create params.email, params.fingerprint
        API.log 'Created user ' + user._id + ' at login'

  #Users.update(user._id,{'roles.__global_roles__':['root']}) if user?._id is "0" and not user.roles.__global_roles__?

  settings = API.settings.service?[params.service]?.accounts ? API.settings.accounts
  settings.cookie ?= API.settings.accounts?.cookie

  if params.service and user?.service?[params.service]?.removed is true
    try Tokens.remove token._id # token can only be tried once
    API.log 'An already removed user ' + user._id + ' tried to access ' + params.service
    return if request then 401 else false
  else if user
    API.log msg: 'Responding with confirmation of login for user', params: params, level: 'debug'
    try API.accounts.fingerprint(user, params.fingerprint, 'login') if params.fingerprint
    API.accounts.addrole(user, params.service+'.user') if params.service and not user.roles?[params.service]?
    if request and API.settings.log.root and user.roles?.__global_roles__? and 'root' in user.roles?.__global_roles__
      API.log msg: 'Root login', notify: subject: 'root user login from ' + request.headers['x-real-ip'], text: 'root user logged in\n\n' + token?.url ? params.url + '\n\n' + request.headers['x-real-ip'] + '\n\n' + request.headers['x-forwarded-for'] + '\n\n'

    _rs = params.resume
    try 
      # a user that gets auth from the main API will already be set, so the above checks for token etc will not run
      # so check to see if the auth'd user already has a valid resume token (which they should)
      if params.resume and params.timestamp
        token = Tokens.find resume: API.accounts.hash(params.resume), timestamp: params.timestamp, action: 'resume'
        API.log 'Authorised user already has a still-valid resume token' if token
    if not token or token.timeout < Date.now() or token.action isnt 'resume'
      try Tokens.remove token._id # get rid of old token
      _rs = Random.hexString 30
      nt = uid: user._id, action: 'resume', resume: API.accounts.hash(_rs), timestamp: Date.now(), timeout: Date.now() + (settings.cookie?.timeout ? 259200) * 60 * 1000
      nt.fingerprint = API.accounts.hash(params.fingerprint) if params.fingerprint
      nt.timeout_date = moment(nt.timeout, "x").format "YYYY-MM-DD HHmm.ss"
      Tokens.insert nt
    else
      nt = token
    services = {}
    services[s] = _.omit(user.service[s], 'private') for s of user.service
    return
      apikey: user.api.keys[0].key
      account:
        email: if params.email then params.email else user.emails[0].address
        createdAt: user.createdAt
        created_date: user.created_date
        updatedAt: user.updatedAt
        updated_date: user.updated_date
        retrievedAt: user.retrievedAt
        retrieved_date: user.retrieved_date
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

API.accounts.password = (password,user,acc) ->
  if not password?
    return false
  else if acc?
    if acc is user?._id or API.accounts.auth 'root', user # TODO who should be allowed to change user passwords other than root?
      Users.update acc, {password: API.accounts.hash(password)}
      return true
    else
      return 401
  else
    Users.update user._id, {password: API.accounts.hash(password)}
    return true

API.accounts.apikey = (apikey,user,acc) ->
  user = API.accounts.retrieve(user) if typeof user is 'string'
  # TODO add a way to only add, reset or remove one apikey? - this currently resets all to just one default
  apikey = Random.hexString 30
  apikeys = [{ key: apikey, hash: API.accounts.hash(apikey), name: 'default' }]
  if acc?
    if acc is user?._id or API.accounts.auth 'root', user # TODO who should be allowed to change user passwords other than root?
      Users.update acc, {'api.keys': apikeys}
      return true
    else
      return 401
  else
    Users.update user._id, {'api.keys': apikeys}
    return true
  
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
    if user.roles.__global_roles__? and 'root' in user.roles.__global_roles__ # root has access to everything
      API.log 'user ' + user._id + ' has role root'
      return 'root'

    if user.roles[group]? and role in user.roles[group]
      API.log 'user ' + user._id + ' has role ' + g
      return role

    # check for higher auth in cascading roles for group - TODO allow cascade on global?
    if cascade and user.roles[group]?
      cascade = ['root', 'service', 'super', 'owner', 'admin', 'auth', 'publish', 'edit', 'read', 'user', 'info', 'public'] if cascade is true
      ri = cascade.indexOf role
      if ri isnt -1
        cascs = cascade.splice 0, ri
        for rl in cascs
          if rl in user.roles[group]
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
    device: [] # user devices associated by device fingerprint can be stored here - removed old devices object as bad mapping
    service: {} # services identified by service name, which can be changed by those in control of the service. Viewable by user unless in private key, but only editable by user if in profile key
    api: keys: [{ key: apikey, hash: API.accounts.hash(apikey), name: 'default' }]
    emails: [{ address: email, verified: true }]
  first = Users.count() is 0
  u._id = "0" if first and API.settings.dev
  u.roles = if first then __global_roles__: ['root'] else {}
  u.device.push {hash: API.accounts.hash(fingerprint), action: 'create', createdAt: Date.now()} if fingerprint
  u._id = Users.insert u
  API.log "Created user " + u._id
  return u # API.accounts.retrieve u._id is it worth doing a retrieve, or just pass back what has been calculated?

API.accounts.retrieve = (val) ->
  if not val?
    return undefined
  else if typeof val is 'object'
    if val.apikey?
      # a convenience for passing in apikey searches - these must be separate and specified, unlike id / email searches, otherwise putting an id as apikey would return a user object
      hashed = API.accounts.hash(val.apikey)
      srch = [{'api.keys.hash.exact': hashed},{'api.keys.hashedToken.exact': hashed}] # old accounts have hashedToken instead of hash
    else if val.password?
      srch = {'password.exact': API.accounts.hash(val.password)}
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
    srch = 'apikey' if typeof val is 'object' and val.apikey?
    API.log msg: 'Retrieved account by ' + JSON.stringify(srch), retrieved: u?._id
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
  if API.accounts.auth 'root', uacc
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

  set = {}
  k = 'roles.' + group
  if user.roles[group]?
    k += '.' + user.roles[group].length
    set[k] = role
  else
    set[k] = [role]

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

# this should be developed further or in combo with a device action, see below comments
API.accounts.fingerprint = (uid, fingerprint, action) ->
  uid = API.accounts.retrieve(uid) if typeof uid is 'string'
  dh = API.accounts.hash(fingerprint)
  uid.device ?= []
  if dh not in _.pluck uid.device, 'hash'
    uid.device.push {hash: dh, action:action, createdAt: Date.now()}
    Users.update(uid._id, device: uid.device)

# TODO should have a function to add/remove emails to an account (no accounts should share emails)
# and a function to change/get/create new API key, as well as one to set/change username (which must also be unique)
# and one to manage the device (could register a device as one to receive tokens on, when logged in on that device)
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



################################################################################
API.add 'accounts/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.accounts.test(this.queryParams.verbose)

API.accounts.test = (verbose) ->
  result = {passed:[],failed:[]}

  console.log('Starting accounts test') if API.settings.dev

  temail = 'a_test_account@noddy.com'
  try
    if old = API.accounts.retrieve temail # clean up old test items
      API.accounts.remove old._id
    Tokens.remove {service: 'TEST'}
    Tokens.remove {email: temail}

  tests = [
    () ->
      result.hash = API.accounts.hash 1234567
      return result.hash is API.accounts.hash 1234567
    () ->
      result.create = API.accounts.create temail
      return typeof result.create is 'object' and result.create?._id?
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.retrieved = API.accounts.retrieve temail
      return result.retrieved._id is result.create._id
    () ->
      result.addrole = API.accounts.addrole result.retrieved._id, 'testgroup.testrole'
      result.addedrole = API.accounts.retrieve result.retrieved._id
      return result.addedrole?.roles?.testgroup?.indexOf('testrole') isnt -1
    () ->
      result.authorised = API.accounts.auth 'testgroup.testrole', result.addedrole
      return result.authorised
    () ->
      result.removerole = API.accounts.removerole result.retrieved._id, 'testgroup.testrole'
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.deauthorised = API.accounts.retrieve result.retrieved._id
      return result.deauthorised.roles.testgroup.length is 0
    () ->
      result.token = API.accounts.token {email:temail,service:'TEST',action:'login'}, false
      return result.token?.email is temail and result.token?.service is 'TEST' and result.token?.token and result.token?.hash
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.logincode = Tokens.find temail
      return result.logincode?.token? and result.logincode.token is API.accounts.hash(result.token.token)
    () ->
      result.login = API.accounts.login {email:temail, token:result.token.token}
      return result.login?.account?.email is temail
    () ->
      result.logincodeRemoved = Tokens.get result.token._id
      return result.logincodeRemoved is undefined
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.loggedinResume = Tokens.find {uid:result.retrieved._id}
      return result.loggedinResume? and result.loggedinResume.resume is API.accounts.hash(result.login?.settings?.resume)
    () ->
      result.logout = API.accounts.logout result.retrieved._id
      return result.logout is true
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.noTokensAfterLogout = Tokens.find {uid:result.retrieved._id}
      return not result.noTokensAfterLogout?
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  try
    if acc = API.accounts.retrieve temail # clean up old test items
      API.accounts.remove acc._id
    Tokens.remove {service: 'TEST'}
    Tokens.remove {email: temail}

  console.log('Ending accounts test') if API.settings.dev

  return result
