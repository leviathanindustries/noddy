
# core docs:
# http://core.ac.uk/docs/
# http://core.ac.uk/docs/#!/articles/searchArticles
# http://core.ac.uk:80/api-v2/articles/search/doi:"10.1186/1471-2458-6-309"

API.use ?= {}
API.use.core = {}

API.add 'use/core/doi/:doipre/:doipost',
  get: () -> return API.use.core.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.add 'use/core/search/:qry',
  get: () -> return API.use.core.search this.urlParams.qry, this.queryParams.from, this.queryParams.size

API.use.core.doi = (doi) ->
  return API.use.core.get 'doi:"' + doi + '"'

API.use.core.title = (title) ->
  return API.use.core.get 'title:"' + doi + '"'

API.use.core.get = (qrystr) ->
  res = API.cache.get qrystr, 'core_get'
  if not res?
    ret = API.use.core.search qrystr
    if ret.total
      res = ret.data[0]
      for i in ret.data
        if i.hasFullText is "true"
          res = i
          break
  if res?
    op = API.use.core.open res, true
    res.open = op.open
    res.blacklist = op.blacklist
    API.cache.save qrystr, 'core_get', res
  return res

API.use.core.search = (qrystr,from,size=10) ->
  # assume incoming query string is of ES query string format
  # assume from and size are ES typical
  # but core only accepts certain field searches:
  # title, description, fullText, authorsString, publisher, repositoryIds, doi, identifiers, language.name and year
  # for paging core uses "page" from 1 (but can only go up to 100?) and "pageSize" defaulting to 10 but can go up to 100
  apikey = API.settings.use.core.apikey
  return { status: 'error', data: 'NO CORE API KEY PRESENT!'} if not apikey
  #var qry = '"' + qrystr.replace(/\w+?\:/g,'') + '"'; # TODO have this accept the above list
  url = 'http://core.ac.uk/api-v2/articles/search/' + qrystr + '?urls=true&apiKey=' + apikey
  url += '&pageSize=' + size if size isnt 10
  url += '&page=' + (Math.floor(from/size)+1) if from
  API.log 'Using CORE for ' + url
  try
    res = HTTP.call 'GET', url, {timeout:10000}
    return if res.statusCode is 200 then { total: res.data.totalHits, data: res.data.data} else { status: 'error', data: res}
  catch err
    return {status: 'error', error: err.toString()}

API.use.core.open = (record,blacklist) ->
  res = {}
  if record.fulltextIdentifier
    res.open = record.fulltextIdentifier
    res.blacklist = API.service.oab?.blacklist(record.fulltextIdentifier) if blacklist
  if res.blacklist or record.fulltextUrls?.length > 0
    for u in record.fulltextUrls
      if u.indexOf('dx.doi.org') is -1 and u.indexOf('core.ac.uk') is -1 and (not res.open? or (res.open.indexOf('.pdf') is -1 and u.indexOf('.pdf') isnt -1))
        res.open = u
      	if res.open?
          try
            resolves = HTTP.call 'HEAD', res.open
          catch
            res.open = undefined
        res.blacklist = API.service.oab?.blacklist(res.open) if blacklist and res.open
        break if res.blacklist is false and res.open.indexOf('.pdf') is -1
  return if blacklist then res else (if res.open then res.open else false)
