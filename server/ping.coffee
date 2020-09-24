

# craft an img link and put it in an email, if the email is viewed as html it will load the URL of the img,
# which actually hits this route, and allows us to record stuff about the event

# so for example for oabutton where this was first created for, an image url like this could be created,
# with whatever params are required to be saved, in addition to the nonce.
# On receipt the pinger will grab IP and try to retrieve location data from that too:
# <img src="https://api.cottagelabs.com/ping/p.png?n=<CURRENTNONCE>service=oabutton&id=<USERID>">

@pings = new API.collection "ping"

API.add 'ping.png',
  get: () ->
    if not API.settings.ping?.nonce? or this.queryParams.n is API.settings.ping.nonce
      data = this.queryParams
      delete data.n
      data.ip = this.request.headers['x-forwarded-for'] ? this.request.headers['cf-connecting-ip'] ? this.request.headers['x-real-ip']
      data.forwarded = this.request.headers['x-forwarded-for']
      try
        res = HTTP.call 'GET', 'http://ipinfo.io/' + data.ip + (if API.settings?.use?.ipinfo?.token? then '?token=' + API.settings.use.ipinfo.token else '')
        info = JSON.parse res.content
        data[k] = info[k] for k of info
        if data.loc
          try
            latlon = data.loc.split(',')
            data.lat = latlon[0]
            data.lon = latlon[1]
      pings.insert data
    img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8BQDwAEgAF/posBPQAAAABJRU5ErkJggg==', 'base64');
    if this.queryParams.red
      img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=', 'base64')
    this.response.writeHead 200,
      'Content-disposition': "inline; filename=ping.png"
      'Content-type': 'image/png'
      'Content-length': img.length
      'Access-Control-Allow-Origin': '*'

    this.response.end img

API.add 'pings',
  get: () -> return pings.search this.queryParams
  post: () -> return pings.search this.bodyParams

API.add 'ping',
  get: () ->
    return API.ping this.request.body.url ? this.queryParams.url
  post: () ->
    return API.ping this.request.body.url ? this.queryParams.url

API.add 'ping/:shortid',
  get: () ->
    if this.urlParams.shortid is 'random' and this.queryParams.url
      # may want to disbale this eventually as it makes it easy to flood the server, if auth is added on other routes
      return API.ping this.queryParams.url, this.urlParams.shortid
    else if exists = pings.get(this.urlParams.shortid) and exists.url?
        count = exists.count ? 0
        count += 1
        pings.update exists._id, {count:count}
        return
          statusCode: 302
          headers:
            'Content-Type': 'text/plain'
            'Location': exists.url
          body: 'Location: ' + exists.url
    else return 404
  put:
    authRequired: true
    action: () ->
      # certain user groups can overwrite a shortlink
      # TODO: overwrite a short link ID that already exists, or error out
  post: () ->
    return API.ping (this.request.body.url ? this.queryParams.url), this.urlParams.shortid
  delete:
    #authRequired: true
    action: () ->
      if exists = pings.get this.urlParams.shortid
        pings.remove exists._id
        return true
      else
        return 404

API.ping = (url,shortid) ->
  return false if not url?
  url = 'http://' + url if url.indexOf('http') isnt 0
  if (not shortid? or shortid is 'random') and spre = pings.find {url:url,redirect:true}
    return spre._id
  else
    obj = {url:url,redirect:true}
    if shortid? and shortid isnt 'random'
      while already = pings.get shortid
        shortid += Random.hexString(2)
      obj._id = shortid
    return pings.insert obj

