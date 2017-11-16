
# use the doaj
# https://doaj.org/api/v1/docs

API.use ?= {}
API.use.doaj = {journals: {}, articles: {}}

API.add 'use/doaj/articles/search/:qry',
  get: () -> return API.use.doaj.articles.search this.urlParams.qry

API.add 'use/doaj/articles/doi/:doipre/:doipost',
  get: () -> return API.use.doaj.articles.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.add 'use/doaj/journals/search/:qry',
  get: () -> return API.use.doaj.journals.search this.urlParams.qry

API.add 'use/doaj/journals/issn/:issn',
  get: () -> return API.use.doaj.journals.issn this.urlParams.issn

API.use.doaj.journals.issn = (issn) ->
  r = API.use.doaj.journals.search 'issn:' + issn
  return if r.data.results?.length then {data: r.data.results[0]} else 404

# title search possible with title:MY JOURNAL TITLE
API.use.doaj.journals.search = (qry,params) ->
  url = 'https://doaj.org/api/v1/search/journals/' + qry + '?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  res = HTTP.call 'GET', url
  return if res.statusCode is 200 then {data: res.data} else {status: 'error', data: res.data}

API.use.doaj.articles.doi = (doi) ->
  return API.use.doaj.articles.get 'doi:' + doi

API.use.doaj.articles.title = (title) ->
  return API.use.doaj.articles.get 'bibjson.title.exact:"' + title + '"'

API.use.doaj.articles.get = (qry) ->
  res = API.cache.get qry, 'doaj_articles_get'
  if not res?
    res = API.use.doaj.articles.search qry
    rec = if res?.data?.results?.length then res.data.results[0] else undefined
    if rec?
      op = API.use.doaj.articles.open rec, true
      rec.open = op.open
      rec.blacklist = op.blacklist
      API.cache.save qry, 'doaj_articles_get', res
      return rec
    return rec
  else
    return res

API.use.doaj.articles.search = (qry,params) ->
  url = 'https://doaj.org/api/v1/search/articles/' + qry + '?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  try
    res = HTTP.call 'GET', url
    return if res.statusCode is 200 then {data: res.data} else {status: 'error', data: res.data}
  catch err
    return {status: 'error', data: 'DOAJ error', error: err}

API.use.doaj.articles.open = (record,blacklist) ->
  res = {}
  if record.bibjson?.link?
    for l in record.bibjson.link
      if l.type is 'fulltext'
        res.open = l.url
        if res.open?
          try
            resolves = HTTP.call 'HEAD', res.open
          catch
            res.open = undefined
        res.blacklist = API.service.oab?.blacklist(res.open) if res.open and blacklist
        break if res.open and not res.blacklist
  return if blacklist then res else (if res.open? then res.open else false)