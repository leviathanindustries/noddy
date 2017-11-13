
# core docs:
# http://core.ac.uk/docs/
# http://core.ac.uk/docs/#!/articles/searchArticles
# http://core.ac.uk:80/api-v2/articles/search/doi:"10.1186/1471-2458-6-309"

API.use ?= {}
API.use.core = {articles:{}}

API.add 'use/core/articles/doi/:doipre/:doipost',
  get: () -> return API.use.core.articles.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.add 'use/core/articles/search/:qry',
  get: () -> return API.use.core.articles.search this.urlParams.qry, this.queryParams.from, this.queryParams.size

API.use.core.articles.doi = (doi) ->
  apikey = API.settings.use.core.apikey
  return { status: 'error', data: 'NO CORE API KEY PRESENT!'} if not apikey
  url = 'https://core.ac.uk/api-v2/articles/search/doi:"' + doi + '"?urls=true&apiKey=' + apikey
  API.log 'Using CORE for ' + url
  try
    res = HTTP.call 'GET', url, {timeout:10000}
    if res.statusCode is 200
      if res.data.totalHits is 0
        return { data: res.data }
      else
        ret = res.data.data[0]
        for i in res.data.data
          if i.hasFullText is "true"
            ret = i
            break
        return { data: ret}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', error: err.toString() }

API.use.core.articles.search = (qrystr,from,size=10) ->
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