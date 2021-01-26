
# use microsoft
@msgraph_paper = new API.collection index: "msgraph", type: "paper", devislive: true
@msgraph_abstract = new API.collection index: "msgraph", type: "abstract", devislive: true
@msgraph_journal = new API.collection index: "msgraph", type: "journal", devislive: true
@msgraph_author = new API.collection index: "msgraph", type: "author", devislive: true
@msgraph_affiliation = new API.collection index: "msgraph", type: "affiliation", devislive: true
@msgraph_relation = new API.collection index: "msgraph", type: "relation", devislive: true

API.add 'use/microsoft', get: () -> return {info: 'returns microsoft things a bit nicer'}

API.add 'use/microsoft/graph/paper', 
  get: () -> return if this.queryParams.title then API.use.microsoft.graph.paper.title(this.queryParams.title) else API.use.microsoft.graph.paper this.queryParams
  post: () -> return API.use.microsoft.graph.paper this.bodyParams
API.add 'use/microsoft/graph/paper/:pid', get: () -> return API.use.microsoft.graph.paper this.urlParams.pid
API.add 'use/microsoft/graph/paper/:doi/:doi2', get: () -> return API.use.microsoft.graph.paper.doi this.urlParams.doi + '/' + this.urlParams.doi2
API.add 'use/microsoft/graph/paper/:doi/:doi2/:doi3', get: () -> API.use.microsoft.graph.paper.doi this.urlParams.doi + '/' + this.urlParams.doi2 + '/' + this.urlParams.doi3

API.add 'use/microsoft/graph/journal', () -> return msgraph_journal.search this
API.add 'use/microsoft/graph/journal/:jid', 
  get: () ->
    if this.urlParams.jid.indexOf('-') isnt -1
      return msgraph_journal.find 'Issn.exact:"' + this.urlParams.jid + '"'
    else
      return msgraph_journal.get this.urlParams.jid

API.add 'use/microsoft/graph/author', () -> return msgraph_author.search this
API.add 'use/microsoft/graph/author/:aid', get: () -> return msgraph_author.get this.urlParams.aid

API.add 'use/microsoft/graph/affiliation', () -> return msgraph_affiliation.search this
API.add 'use/microsoft/graph/affiliation/:aid', get: () -> return msgraph_affiliation.get this.urlParams.aid

API.add 'use/microsoft/graph/relation', 
  get: () -> return API.use.microsoft.graph.relation this.queryParams
  post: () -> return API.use.microsoft.graph.relation this.bodyParams
API.add 'use/microsoft/graph/relation/:rid', () -> return API.use.microsoft.graph.relation this.urlParams.rid

API.add 'use/microsoft/graph/import', post: () -> return API.use.microsoft.graph.import this.queryParams.what, this.request.body

API.add 'use/microsoft/academic/evaluate', get: () -> return API.use.microsoft.academic.evaluate this.queryParams

API.add 'use/microsoft/bing/search', get: () -> return API.use.microsoft.bing.search this.queryParams.q
API.add 'use/microsoft/bing/entities', get: () -> return API.use.microsoft.bing.entities this.queryParams.q

API.use ?= {}
API.use.microsoft = {}
API.use.microsoft.academic = {}
API.use.microsoft.bing = {}
API.use.microsoft.graph = {}

API.use.microsoft.graph.relation = (q, papers=true, authors=true, affiliations=true) ->
 # ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
 # context could be paper, author, affiliation
  results = []
  _append = (recs) ->
    res = []
    recs = [recs] if not Array.isArray recs
    for rec in recs
      rec.paper = msgraph_paper.get(rec.PaperId) if rec.PaperId and papers
      rec.author = msgraph_author.get(rec.AuthorId) if rec.AuthorId and authors
      rec.affiliation = msgraph_affiliation.get(rec.AffiliationId ? rec.LastKnownAffiliationId) if (rec.AffiliationId or rec.LastKnownAffiliationId) and affiliations
      if rec.GridId or rec.affiliation?.GridId
        rec.ror = API.use.wikidata.grid2ror rec.GridId ? rec.affiliation?.GridId
      res.push rec
      results.push rec
    return res

  if typeof q is 'string' and rel = msgraph_relation.get q
    return _append rel
  
  count = 0
  if typeof q is 'string' and cn = msgraph_relation.count 'PaperId.exact:"' + q + '"'
    count += cn
    _append(msgraph_relation.fetch('PaperId.exact:"' + q + '"')) if cn < 10
  else if typeof q is 'string' and cn = msgraph_relation.count 'AuthorId.exact:"' + q + '"'
    count += cn
    _append(msgraph_relation.fetch('AuthorId.exact:"' + q + '"')) if cn < 10
  else if typeof q is 'string' and cn = msgraph_relation.count 'AffiliationId.exact:"' + q + '"'
    count += cn
    _append(msgraph_relation.fetch('AffiliationId.exact:"' + q + '"')) if cn < 10

  if typeof q is 'string' and count
    return if results.length then results else count
  else
    return msgraph_relation.search q
  
API.use.microsoft.graph.paper = (q) ->
  # NOTE: although there are about 250m papers only about 90m have JournalId - the rest could be books, etc
  _append = (rec) ->
    if rec.JournalId and j = msgraph_journal.get rec.JournalId
      rec.journal = j
    if ma = msgraph_abstract.get rec.PaperId
      rec.abstract = ma
    rec.relation = API.use.microsoft.graph.relation rec.PaperId, false, false
    return rec

  if typeof q is 'string' and q.indexOf('/') isnt -1 and paper = msgraph_paper.find 'Doi.exact:"' + q + '"'
    return _append paper
  else if typeof q is 'string' and paper = msgraph_paper.get q
    return _append paper
  else
    return msgraph_paper.search q

API.use.microsoft.graph.paper.doi = (doi) ->
  if res = API.use.microsoft.graph.paper doi
    if res.Doi
      return res
  return undefined

API.use.microsoft.graph.paper.title = (title) ->
  title = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim() # MAG PaperTitle is lowercased. OriginalTitle isnt
  if res = msgraph_paper.find 'PaperTitle:"' + title + '"'
    rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
    if typeof API.tdm?.levenshtein is 'function'
      lvs = API.tdm.levenshtein title, rt, false
      longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
      if lvs.distance < 2 or longest/lvs.distance > 10
        return API.use.microsoft.graph.paper res.PaperId
    else if title.length < (rt.length * 1.2) and (title.length > rt.length * .8)
      return API.use.microsoft.graph.paper res.PaperId
  return undefined

# https://docs.microsoft.com/en-us/academic-services/graph/reference-data-schema
# MS academic graph is a bit annoyingly hard to use, but the raw data is more useful. Getting the raw data 
# is a hassle too though they only distribute it via azure. We get files from there and run an import script 
# that sends them here. Fields we get are:
# 'journal': ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
# 'author': ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
# 'paper': ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate'],
# 'affiliation': ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate'],
# 'relation': ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']

# of about 49k journals about 9 are dups, 37k have ISSN. 32k of them are already in our catalogue
# of about 250m papers, about 99m have DOIs
API.use.microsoft.graph.import = (what='journal', recs) ->
  if _.isArray(recs) and recs.length
    if what is 'journal'
      return msgraph_journal.insert recs
    else if what is 'author'
      return msgraph_author.insert recs
    else if what is 'paper'
      return msgraph_paper.insert recs
    else if what is 'affiliation'
      return msgraph_affiliation.insert recs
    else if what is 'relation'
      return msgraph_relation.insert recs
    else if what is 'abstract'
      return msgraph_abstract.insert recs
  else
    return undefined



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
        API.http.cache(q, 'bing_search', ret) if cache and ret.total
        return ret
      else
        return { status: 'error', data: res.data}
    catch err
      return { status: 'error', data: 'error', error: err}

# https://docs.microsoft.com/en-gb/azure/cognitive-services/bing-news-search/nodejs