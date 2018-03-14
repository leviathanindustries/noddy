
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
        dets = msg: 'Login attempt by ' + (if xid then xid else 'unknown') + ' to ' + this.request.url.split('apikey=')[0] + ' from ' + this.request.headers['x-forwarded-for'] + ' ' + this.request.headers['x-real-ip']
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

API.blacklist = (request,stale=3600000) ->
  # TODO could add blacklisting by stored values in an index, instead of or in addition to from a google sheet
  try
    if API.settings.blacklist?.disabled
      return false
    else if API.settings.blacklist?.sheet
      blacklist = API.use.google.sheets.feed API.settings.blacklist.sheet, stale
      if request?
        for b in blacklist
          bad = false
          routematch = not b.route or (b.route and b.route isnt '*' and request.url.toLowerCase().indexOf(b.route.toLowerCase()) isnt -1)
          if b.key and b.key not in ['headers','params','body'] and b.value and routematch
            blc = b.key.toLowerCase()
            vlc = b.value.toLowerCase()
            for h of request.headers
              if not bad and (b is '*' or h.toLowerCase() is blc) and JSON.stringify(request.headers[h]).toLowerCase().indexOf(vlc) isnt -1
                bad = true
            if bad is false
              for p of request.query
                if not bad and (p is '*' or p.toLowerCase() is blc) and JSON.stringify(request.query[p]).toLowerCase().indexOf(vlc) isnt -1
                  bad = true
            if bad is false
              for d of request.body
                if not bad and (d is '*' or d.toLowerCase() is blc) and JSON.stringify(request.body[d]).toLowerCase().indexOf(vlc) isnt -1
                  bad = true
          else if b.key and b.key in ['headers','params','body'] and b.value and routematch and JSON.stringify(request[(if b.key is 'params' then 'query' else b.key)]).toLowerCase().indexOf(b.value.toLowerCase()) isnt -1
            bad = true
          else if b.value and routematch
            bad = (JSON.stringify(request.headers) + JSON.stringify(request.query) + JSON.stringify(request.body)).toLowerCase().indexOf(b.value.toLowerCase()) isnt -1
          else if b.route and routematch
            bad = true
          if bad
            if API.settings.dev
              # don't write logs cos if blacklisting due to bombardment, logs would put load on the system
              console.log 'Blacklisting'
              console.log request.headers
              console.log request.query
              console.log request.body
              console.log request.url
              console.log b
            try
              parsed = parseInt b.code
              b.code = parsed if not isNaN parsed
              b.code = undefined if b.code is ""
            return
              statusCode: b.code ? 403
              body: {status:'error', error:'blacklisted', info: b.msg ? (b.value ? 'This request') + ' is blacklisted.', contact: b.contact ? API.settings.blacklist.contact}
        return false
      else
        return blacklist
    else
      return false
  catch
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
    return true

API.add 'blacklist',
  get: () ->
    return API.blacklist()
  post: () ->
    # just here to test by POSTing things to it
    return API.blacklist()

API.add 'blacklist/reload',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      return API.blacklist undefined, 1




