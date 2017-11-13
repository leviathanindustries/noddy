
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
  url = 'https://doaj.org/api/v1/search/articles/doi:' + doi
  API.log 'Using doaj for ' + url
  try
    res = HTTP.call 'GET',url
    return if res.statusCode is 200 and res.data?.results?.length > 0 then {data: res.data.results[0]} else {status: 'error', data: res.data}
  catch err
    return {status: 'error', data: 'DOAJ error', error: err}

API.use.doaj.articles.search = (qry,params) ->
  url = 'https://doaj.org/api/v1/search/articles/' + qry + '?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  try
    res = HTTP.call 'GET', url
    return if res.statusCode is 200 then {data: res.data} else {status: 'error', data: res.data}
  catch err
    return {status: 'error', data: 'DOAJ error', error: err}
