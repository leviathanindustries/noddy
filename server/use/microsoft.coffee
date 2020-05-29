
# use microsoft

API.add 'use/microsoft', get: () -> return {info: 'returns microsoft things a bit nicer'}

API.add 'use/microsoft/academic/evaluate', get: () -> return API.use.microsoft.academic.evaluate this.queryParams

API.add 'use/microsoft/bing/search', get: () -> return API.use.microsoft.bing.search this.queryParams.q
API.add 'use/microsoft/bing/entities', get: () -> return API.use.microsoft.bing.entities this.queryParams.q

API.use ?= {}
API.use.microsoft = {}
API.use.microsoft.academic = {}
API.use.microsoft.bing = {}

# MS academic graph is a bit annoyingly hard to use, but the raw data is more useful. Getting the raw data 
# is a hassle too though they only distribute it via azure. However the open academic graph has dumps about a year 
# out of date, which may be sufficient enough to get the coverage we want (which isn't actually article-level, we 
# get that from crossref etc, instead we want affiliations etc). So, work on getting all the open graph dumps and 
# build a local index to query instead
# https://www.openacademic.ai/oag/

# https://docs.microsoft.com/en-gb/azure/cognitive-services/academic-knowledge/queryexpressionsyntax
# https://docs.microsoft.com/en-gb/azure/cognitive-services/academic-knowledge/paperentityattributes
# https://westus.dev.cognitive.microsoft.com/docs/services/56332331778daf02acc0a50b/operations/5951f78363b4fb31286b8ef4/console
# https://portal.azure.com/#resource/subscriptions

API.use.microsoft.academic.evaluate = (qry, attributes='Id,Ti,Y,D,CC,W,AA.AuN,J.JN,E') ->
  # things we accept as query params have to be translated into MS query expression terminology
  # we will only do the ones we need to do... for now that is just title :)
  # It does not seem possible to search on the extended metadata such as DOI, 
  # and extended metadata always seems to come back as string, so needs converting back to json
  expr = ''
  for t of qry
    expr = encodeURIComponent("Ti='" + qry[t] + "'") if t is 'title'
  url = 'https://api.labs.cognitive.microsoft.com/academic/v1.0/evaluate?expr='+expr + '&attributes=' + attributes
  API.log 'Using microsoft academic for ' + url
  try
    res = HTTP.call 'GET', url, {headers: {'Ocp-Apim-Subscription-Key': API.settings.use.microsoft.academic.key}}
    if res.statusCode is 200
      for r in res.data.entities
        r.extended = JSON.parse(r.E) if r.E
        r.converted = {
          title: r.Ti,
          journal: r.J?.JN,
          author: []
        }
        r.converted.author.push({name:r.AA[a].AuN}) for a in r.AA
        try r.converted.url = r.extended.S[0].U
        # TODO could parse more of extended into converted, and change result to just converted if we don't need the original junk
      return res.data
    else
      return { status: 'error', data: res.data}
  catch err
    return { status: 'error', data: 'error', error: err}



# https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-entities-api-v7-reference
API.use.microsoft.bing.entities = (q) ->
  url = 'https://api.cognitive.microsoft.com/bing/v7.0/entities?mkt=en-GB&q=' + q
  API.log 'Using microsoft entities for ' + url
  try
    res = HTTP.call 'GET', url, {timeout: 10000, headers: {'Ocp-Apim-Subscription-Key': API.settings.use.microsoft.bing.key}}
    if res.statusCode is 200
      return res.data
    else
      return { status: 'error', data: res.data}
  catch err
    return { status: 'error', data: 'error', error: err}


# https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-web-api-v7-reference#endpoints
# annoyingly Bing search API does not provide exactly the same results as the actual Bing UI.
# and it seems the bing UI is sometimes more accurate
API.use.microsoft.bing.search = (q, cache=false, refresh, key=API.settings.use.microsoft.bing.key) ->
  if cache and cached = API.http.cache q, 'bing_search', undefined, refresh
    cached.cache = true
    return cached
  else
    url = 'https://api.cognitive.microsoft.com/bing/v7.0/search?mkt=en-GB&count=20&q=' + q
    API.log 'Using microsoft bing for ' + url
    try
      res = HTTP.call 'GET', url, {timeout: 10000, headers: {'Ocp-Apim-Subscription-Key': key}}
      if res.statusCode is 200 and res.data.webPages?.value
        ret = {total: res.data.webPages.totalEstimatedMatches, data: res.data.webPages.value}
        API.http.cache(pmcid, 'bing_search', ret) if cache and ret.total
        return ret
      else
        return { status: 'error', data: res.data}
    catch err
      return { status: 'error', data: 'error', error: err}

# https://docs.microsoft.com/en-gb/azure/cognitive-services/bing-news-search/nodejs