

import oauth from 'oauth'

# http://api.thenounproject.com/explorer

API.use ?= {}
API.use.noun = {}

API.add 'use/noun/search', get: () -> return API.use.noun.search this.queryParams
API.add 'use/noun/icon/:term', get: () -> return API.use.noun.icon this.urlParams.term, this.queryParams.set
API.add 'use/noun/icons/:term', get: () -> return API.use.noun.icon this.urlParams.term
API.add 'use/noun/svg/:term', get: () -> return API.use.noun.svg this.urlParams.term, this.queryParams.set

API.use.noun.svg = (term,set) ->
  res = API.http.cache(term, 'noun_svg') if not set?
  if not res?
    res = API.use.noun.icon (if set? then set else term)
    if res?.icon?.icon_url?
      try
        res = HTTP.call 'GET', res.icon.icon_url
        res = res.content
        API.http.cache(term, 'noun_svg', res) if res?
    else
      return undefined
  return
    statusCode: 200
    headers:
      'Content-Type': 'image/svg+xml'
    body: res

API.use.noun.icon = (term,set) ->
  #res = API.http.cache(term, 'noun_icon') if not set?
  #if not res?
  if true
    res = API.use.noun.search {icon:(if set? then set else term)}
    if res?.icon?
      API.http.cache term, 'noun_icon', res
    else
      return {}
  return res

API.use.noun.icons = (term) ->
  #res = API.http.cache term, 'noun_icons'
  #if not res?
  if true
    res = API.use.noun.search {icons:term}
    if res?.icons?
      API.http.cache term, 'noun_icons', res
    else
      return {}
  return res

_noun_authd = false
_nounget = (url,callback) ->
  if _noun_authd is false
    _noun_authd = new oauth.OAuth(
      'http://api.thenounproject.com',
      'http://api.thenounproject.com',
      API.settings.use.noun.key,
      API.settings.use.noun.secret,
      '1.0',
      null,
      'HMAC-SHA1'
    )
  _noun_authd.get(
    url,
    null,
    null,
    (e, data, res) ->
      if e?
        API.log(e)
        callback null, { status: 'error', data: 'noun project API error', error: e}
      else
        callback null, JSON.parse(data)
  )
_anounget = Meteor.wrapAsync _nounget

API.use.noun.search = (params) ->
  return {} if JSON.stringify(params) is '{}'
  url = 'http://api.thenounproject.com/' #icon/6324'
  if params.icons?
    url += 'icons/' + params.icons
  else if params.icon?
    url += 'icon/' + params.icon
  API.log 'Using noun project for ' + url
  # search_for is required
  try
    res = _anounget url
    if not res?.icon? and not res?.icons? and url.indexOf('ing') isnt -1
      try
        res = _anounget url.replace('ing','')
        if not res?.icon? and not res?.icons?
          try
            res = _anounget url.replace('ing','e')
      catch
        try
          res = _anounget url.replace('ing','e')
    return res
  catch err
    if url.indexOf('ing') isnt -1
      try
        return _anounget url.replace('ing','')
      catch
        try
          return _anounget url.replace('ing','e')
    return { status: 'error', data: 'noun project API error', error: err}


