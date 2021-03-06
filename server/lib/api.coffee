
# api login example:
# curl -X GET "http://api.cottagelabs.com/accounts" -H "x-id: vhi5m4NJbJF7bRXqp" -H "x-apikey: YOURAPIKEYHERE"
# curl -X GET "http://api.cottagelabs.com/accounts?id=vhi5m4NJbJF7bRXqp&apikey=YOURAPIKEYHERE"

@API = new Restivus
  version: '',
  defaultHeaders: { 'Content-Type': 'application/json; charset=utf-8' },
  prettyJson: true,
  auth:
    #token: 'api.keys.hash' # not needed any more
    user: () ->
      console.log('API checking auth') if API.settings.log?.level is 'debug'

      xapikey = this.request.headers['x-apikey'] ? this.request?.query?.apikey ? this.request?.query?.apiKey
      u = API.accounts.retrieve({apikey:xapikey}) if xapikey
      xid = u._id if API.settings.accounts?.email and this.request?.query?.email and u?.emails[0].address is this.request.query.email
      xid ?= this.request?.query?.id
      xid ?= this.request.headers['x-id'] if this.request?.headers?
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

      if not xid and this.request.headers?.cookie and API.settings.accounts?.cookie?.name
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
        dets = msg: 'Login attempt by ' + (if xid then xid else 'unknown') + ' to ' + this.request.url.split('apikey=')[0] + ' from ' + this.request.headers['x-forwarded-for'] + ' ' + this.request.headers['cf-connecting-ip'] + ' ' + this.request.headers['x-real-ip']
        if xid and xapikey and API.settings.log.root and u?.roles?.__global_roles__? and 'root' in u.roles.__global_roles__
          dets.notify = subject: 'API root login ' + this.request.headers['x-forwarded-for'] + ' ' + this.request.headers['cf-connecting-ip'] + ' ' + this.request.headers['x-real-ip']
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

API.add '/',
  get: () ->
    res =
      time: Date.now()
      name: if API.settings.name then API.settings.name else 'API'
      version: if API.settings.version then API.settings.version else "0.0.1"
      dev: API.settings.dev
      listing: []
    rts = {}
    for k in API._routes
      if k.path.indexOf('scripts/') is -1 and k.path isnt 'test' and k.path.indexOf('test/') is -1 and k.path.indexOf('/test') is -1 and k.path.indexOf(':r0') is -1 and k.path isnt '/'
        #info = k.path
        rts[k.path] = k.endpoints
        #  if ky isnt 'options' and ky isnt 'desc'
        #    info += ' ' + ky.toUpperCase()
        #    info += if k.endpoints[ky].roleRequired then '(' + k.endpoints[ky].roleRequired + ') ' else (if k.endpoints[ky].authRequired then '(R) ' else (if k.endpoints[ky].authOptional then '(O) ' else ' '))
        #    info += ' ' + k.endpoints[ky].desc if k.endpoints[ky].desc
        #info += ' ' + k.endpoints.desc if k.endpoints.desc
        res.listing.push k.path #info.trim().trim(',').replace(/  /g,' ')
        # have an auth filter to this route so only shows what the user can actually access
        # note though that some endpoints further filter the user capabilities even if no specific auth is listed
    res.listing.sort()
    res.routes = {}
    #service = {}
    #use = {}
    for rt in res.listing
      srt = rt #rt.replace('service/','').replace('use/','')
      tgt = res.routes #if rt.indexOf('service/') is 0 then service else if rt.indexOf('use/') is 0 then use else res.routes
      ep = JSON.parse JSON.stringify rts[rt]
      delete ep.options
      for tp in ['get','post','put','delete']
        try ep[tp].auth = if ep[tp].roleRequired then ep[tp].roleRequired else if ep[tp].authRequired then 'required' else if ep[tp].authOptional then 'optional' else false
        try delete ep[tp].roleRequired
        try delete ep[tp].authRequired
        try delete ep[tp].authOptional
      #if ep.get? and not ep.post and not ep.put and not ep.delete
      #  ep.get.desc ?= ep.desc
      #  ep = ep.get
      tgt[srt] = ep
    #res.service = service
    #res.use = use
    delete res.listing
    return res





