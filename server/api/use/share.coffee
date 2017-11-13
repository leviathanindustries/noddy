
# https://share.osf.io/api/v2/search/abstractcreativework/_search
# list of sources that Share gets from:
# https://share.osf.io/api/v2/search/creativeworks/_search?&source=%7B%22query%22%3A%7B%22filtered%22%3A%7B%22query%22%3A%7B%22bool%22%3A%7B%22must%22%3A%5B%7B%22match_all%22%3A%7B%7D%7D%5D%7D%7D%7D%7D%2C%22from%22%3A0%2C%22size%22%3A0%2C%22aggs%22%3A%7B%22sources%22%3A%7B%22terms%22%3A%7B%22field%22%3A%22sources%22%2C%22size%22%3A200%7D%7D%7D%7D

API.use ?= {}
API.use.share = {}

API.add 'use/share/search', get: () -> return API.use.share.search this.queryParams

API.add 'use/share/doi/:doipre/:doipost',
  get: () -> return API.use.share.doi this.urlParams.doipre + '/' + this.urlParams.doipost,this.queryParams.open


API.use.share.doi = (doi,open) ->
  res = API.use.share.search {q:'identifiers:"' + doi.replace('/','\/') + '"'}
  if res.total > 0
    rec = if not open or ( open and API.use.share.open(res.data[0]) ) then res.data[0] else undefined
    return {data: rec}
  else
    return {}

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

API.use.share.open = (record) ->
  sheet = API.use.google.sheets.feed API.settings.openaccessbutton.share_sources_sheetid
  sources = []
  sources.push(i.name.toLowerCase()) for i in sheet
  for s in record.sources
    if s not in sources
      d
      for id in record.identifiers
        if id.indexOf('http') is 0
          if id.indexOf('doi.org') is -1
            if bl = API.service.oab.blacklist(i.webresource.url.$) isnt true
              return if bl then bl else id
          else if not d?
            d = id
      return d if d?
  return false




