
# https://share.osf.io/api/v2/search/abstractcreativework/_search
# list of sources that Share gets from:
# https://share.osf.io/api/v2/search/creativeworks/_search?&source=%7B%22query%22%3A%7B%22filtered%22%3A%7B%22query%22%3A%7B%22bool%22%3A%7B%22must%22%3A%5B%7B%22match_all%22%3A%7B%7D%7D%5D%7D%7D%7D%7D%2C%22from%22%3A0%2C%22size%22%3A0%2C%22aggs%22%3A%7B%22sources%22%3A%7B%22terms%22%3A%7B%22field%22%3A%22sources%22%2C%22size%22%3A200%7D%7D%7D%7D

API.use ?= {}
API.use.share = {}

API.add 'use/share/search', get: () -> return API.use.share.search this.queryParams

API.add 'use/share/doi/:doipre/:doipost',
  get: () -> return API.use.share.doi this.urlParams.doipre + '/' + this.urlParams.doipost


API.use.share.doi = (doi) ->
  return API.use.share.get {q:'identifiers:"' + doi.replace('/','\/') + '"'}

API.use.share.title = (title) ->
  return API.use.share.get {q:title}

API.use.share.get = (params) ->
  res = API.use.share.search params
  res = if res.total then res.data[0] else undefined
  if res?
    op = API.use.share.redirect res
    res.url = op.url
    res.redirect = op.redirect
  return res

API.use.share.search = (params) ->
  url = 'https://share.osf.io/api/v2/search/creativeworks/_search?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using share for ' + url
  try
    res = HTTP.call 'GET', url, {headers:{'Content-Type':'application/json'}}
    if res.statusCode is 200
      ret = []
      ret.push(r._source) for r in res.data.hits.hits
      return { total: res.data.hits.total, data: ret}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', data: 'SHARE API error', error: err}

API.use.share.redirect = (record) ->
  possible = {}
  sources = []
  if API.settings.service?.openaccessbutton?.google?.sheets?.share?
    sources.push(i.name.toLowerCase()) for i in API.use.google.sheets.feed(API.settings.service.openaccessbutton.google.sheets.share)
  for s in record.sources
    if s in sources or sources.length is 0
      for id in record.identifiers
        if id.indexOf('http') is 0 and not possible.url?
          possible = {url: id}
          possible.redirect = API.service.oab.redirect(id) if API.service.oab?
          break if possible.redirect isnt false and id.indexOf('doi.org') is -1
  return possible




