
# api login example:
# curl -X GET "http://api.cottagelabs.com/accounts" -H "x-id: vhi5m4NJbJF7bRXqp" -H "x-apikey: YOURAPIKEYHERE"
# curl -X GET "http://api.cottagelabs.com/accounts?id=vhi5m4NJbJF7bRXqp&apikey=YOURAPIKEYHERE"

@API = new Restivus
  version: '',
  defaultHeaders: { 'Content-Type': 'application/json; charset=utf-8' },
  prettyJson: true,
  auth:
    token: 'api.keys.hash'
    user: () ->
      console.log('API checking auth') if API.settings.log?.level is 'debug'

      xapikey = this.request.headers['x-apikey'] ? this.request.query.apikey
      u = API.accounts.retrieve({apikey:xapikey}) if xapikey
      xid = u._id if API.settings.accounts?.email and this.request.query.email and u?.emails[0].address is this.request.query.email
      xid ?= this.request.query.id
      xid ?= this.request.headers['x-id']
      xid = undefined if API.settings.accounts?.xid and u?._id isnt xid
      xid = u._id if u and not API.settings.accounts?.xid
      console.log('Auth by header/param ' + xid + ' ' + xapikey + ' ' + (if u then u._id)) if API.settings.log?.level is 'debug' and xid

      if not xid and this.request.body?.resume and this.request.body?.timestamp
        console.log('Trying auth by resume and timestamp in request body') if API.settings.log?.level is 'debug'
        tok = Tokens.find resume: API.accounts.hash(this.request.body.resume), timestamp: this.request.body.timestamp, action: 'resume'
        if tok
          u = API.accounts.retrieve tok.uid
          if u
            xid = u._id
            xapikey = u.api.keys[0].key
            console.log('Auth by resume and timestamp in request body ' + xid + ' ' + xapikey + ' ' + (if u then u._id)) if API.settings.log?.level is 'debug'

      if not xid and this.request.headers.cookie and API.settings.accounts?.cookie?.name
        console.log('Trying cookie auth') if API.settings.log?.level is 'debug'
        try
          cookie = JSON.parse(decodeURIComponent(this.request.headers.cookie).split(API.settings.accounts.cookie.name+"=")[1].split(';')[0])
          console.log(cookie) if API.settings.log?.level is 'debug'
          tok = Tokens.find resume: API.accounts.hash(cookie.resume), timestamp: cookie.timestamp, action: 'resume'
          if tok
            u = API.accounts.retrieve tok.uid
            if u
              xid = u._id
              xapikey = u.api.keys[0].key
              console.log('Auth by cookie ' + xid + ' ' + xapikey + ' ' + (if u then u._id)) if API.settings.log?.level is 'debug'

      if not this.authOptional
        dets = msg: 'Login attempt by ' + (if xid then xid else 'unknown') + ' to ' + this.request.url + ' from ' + this.request.headers['x-forwarded-for'] + ' ' + this.request.headers['x-real-ip']
        if xid and xapikey and API.settings.log.root and u?.roles?.__global_roles__? and 'root' in u.roles.__global_roles__
          dets.notify = subject: 'API root login ' + this.request.headers['x-real-ip']
          dets.msg = dets.msg.replace 'Login attempt ', 'ROOT login '
        else if xid and xapikey
          dets.msg = dets.msg.replace 'Login attempt ', 'Login '
        API.log dets
        # TODO if login tracking / user online status is to be tracked, could be done here (as well as possibly by accounts/ping) or is logging enough?
      return
        user: if xid and xapikey then u
        userId: xid
        token: if xapikey then API.accounts.hash(xapikey)

API.settings = Meteor.settings

API.blacklist = (request) ->
  # TODO could add blacklisting by stored values in an index, instead of or in addition to from a google sheet
  if API.settings.blacklist?.disabled
    return false
  else if API.settings.blacklist?.sheet
    blacklist = API.use.google.sheets.feed API.settings.blacklist.sheet
    if request?
      for b in blacklist
        check = if b.key and b.key isnt '*' then (request.headers[b.key] ? request.params[b.key]) else JSON.stringify(request.headers) + JSON.stringify(request.params)
        if check and b.value and check.indexOf(b.value) isnt -1
          try parseInt b.code
          return
            statusCode: b.code ? 403
            headers:
              'Content-Type': 'text/plain'
            body: b.msg ? b.value + ' is blacklisted.' + (if API.settings.blacklist.contact then ' Contact ' + API.settings.blacklist.contact + ' for further information.' else '')
    else
      return blacklist
  else
    return false

API.add '/',
  get: () ->
    res =
      name: if API.settings.name then API.settings.name else 'API'
      version: if API.settings.version then API.settings.version else "0.0.1"
    res.routes = []
    for k in API._routes
      if k.path.indexOf('/test') is -1 and k.path.indexOf(':r0') is -1 and k.path isnt '/' and k.path isnt 'test'
        info = k.path
        for ky of k.endpoints
          if ky isnt 'options' and ky isnt 'desc'
            info += ' ' + ky.toUpperCase()
            info += if k.endpoints[ky].roleRequired then '(' + k.endpoints[ky].roleRequired + ') ' else (if k.endpoints[ky].authRequired then '(R) ' else (if k.endpoints[ky].authOptional then '(O) ' else ' '))
            info += ' ' + k.endpoints[ky].desc if k.endpoints[ky].desc
        info += ' ' + k.endpoints.desc if k.endpoints.desc
        res.routes.push info.trim().trim(',').replace(/  /g,' ')
        # have an auth filter to this route so only shows what the user can actually access
        # note though that some endpoints further filter the user capabilities even if no specific auth is listed
    res.routes.sort()
    return res
