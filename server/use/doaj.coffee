

# use the doaj
# https://doaj.org/api/v1/docs

API.use ?= {}
API.use.doaj = {journals: {}, articles: {}}

API.add 'use/doaj/:which/es',
  get: () -> return API.use.doaj.es this.urlParams.which, this.queryParams, undefined, this.queryParams.format isnt 'false'
  post: () -> return API.use.doaj.es this.urlParams.which, this.queryParams, this.bodyParams, this.queryParams.format isnt 'false'

API.add 'use/doaj/articles/search/:qry',
  get: () -> return API.use.doaj.articles.search this.urlParams.qry, this.queryParams, this.queryParams.format isnt 'false'

API.add 'use/doaj/articles/title/:qry',
  get: () -> return API.use.doaj.articles.title this.urlParams.qry

API.add 'use/doaj/articles/doi/:doipre/:doipost',
  get: () -> return API.use.doaj.articles.doi this.urlParams.doipre + '/' + this.urlParams.doipost, this.queryParams.format isnt 'false'
API.add 'use/doaj/articles/doi/:doipre/:doipost/:doiextra',
  get: () -> return API.use.doaj.articles.doi this.urlParams.doipre + '/' + this.urlParams.doipost + '/' + this.urlParams.doiextra, this.queryParams.format isnt 'false'

API.add 'use/doaj/journals/search/:qry',
  get: () -> return API.use.doaj.journals.search this.urlParams.qry

API.add 'use/doaj/journals/issn/:issn',
  get: () -> return API.use.doaj.journals.issn this.urlParams.issn



API.use.doaj.es = (which='journal,article', params, body, format=true) ->
  # which could be journal or article or journal,article
  # but doaj only allows this type of query on journal,article, so will add this later as a query filter
  url = 'https://doaj.org/query/journal,article/_search?ref=public_journal_article&'
  # this only works with a source param, if one is not present, should convert the query into a source param
  if body
    for p of params
      body[p] = params[p] # allow params to override body?
  else
    body = params
  if body.format?
    delete body.format
    format ?= true
  if not body.source?
    tr = API.collection._translate body
    body = source: tr # unless doing a post, in which case don't do this part
    body.source.aggs ?= {} # requier this to get doaj to accept the query
    body.source.query.filtered.query.bool.must.push({term: {_type: which}}) if which isnt 'journal,article'
    #body.source.query = body.source.query.filtered.query.bool.must[0]
    #body.source.query ?= {query_string: {query: ""}}
  url += op + '=' + encodeURIComponent(JSON.stringify(body[op])) + '&' for op of body
  API.log 'Using doaj ES for ' + url
  try
    res = HTTP.call 'GET', url
    try res.data.query = body
    if res.statusCode is 200
      if format
        res.data = res.data.hits
        for d of res.data.hits
          res.data.hits[d] = API.use.doaj.articles.format res.data.hits[d]._source
        res.data.data = res.data.hits
        delete res.data.hits
      return res.data
    else
      return {status: 'error', data: res.data, query: body}
  catch err
    return {status: 'error', error: err, query: body, url: url}

API.use.doaj.journals.issn = (issn) ->
  r = API.use.doaj.journals.search 'issn:' + issn
  return if r.data?.length then r.data[0] else undefined

# title search possible with title:MY JOURNAL TITLE
# DOAJ API rate limit is 6r/s
# a 200ms limit would stay above that, and also the noddy limiter sets a min of 500ms anyway, and actually only runs one task per second if just one machine running
API.use.doaj.journals.search = (qry,params) ->
  url = 'https://doaj.org/api/v1/search/journals/' + qry + '?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  res = API.job.limit 200, 'HTTP.call', ['GET',url], "DOAJ"
  #res = HTTP.call 'GET', url
  return if res.statusCode is 200 then res.data else {status: 'error', data: res.data}

API.use.doaj.articles.doi = (doi, format) ->
  return API.use.doaj.articles.get 'doi:' + doi, format

API.use.doaj.articles.title = (title,format) ->
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  return API.use.doaj.articles.get 'title:"' + title + '"', format

API.use.doaj.articles.get = (qry,format=true) ->
  res = API.use.doaj.articles.search qry, undefined, false
  rec = if res?.data?.length then res.data[0] else undefined
  if rec?
    op = API.use.doaj.articles.redirect rec
    rec.url = op.url
    rec.redirect = op.redirect
  return if format then API.use.doaj.articles.format(rec) else rec

API.use.doaj.articles.search = (qry,params={},format=true) ->
  url = 'https://doaj.org/api/v1/search/articles/' + qry + '?'
  #params.sort ?= 'bibjson.year:desc'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  try
    #res = HTTP.call 'GET', url
    res = API.job.limit 200, 'HTTP.call', ['GET',url], "DOAJ"
    if res.statusCode is 200
      if format
        for d of res.data.results
          res.data.results[d] = API.use.doaj.articles.format res.data.results[d]
      res.data.data = res.data.results
      delete res.data.results
      return res.data
    else 
      return {status: 'error', data: res.data}
  catch err
    return {status: 'error', data: 'DOAJ error', error: err}

API.use.doaj.articles.redirect = (record) ->
  res = {}
  if record.bibjson?.link?
    for l in record.bibjson.link
      if l.type is 'fulltext'
        res.url = l.url
        if res.url?
          try
            resolves = HTTP.call 'HEAD', res.url, {timeout: API.settings.use?.doaj?.timeout ? API.settings.use?._timeout ? 2000}
          catch
            res.url = undefined
        res.redirect = API.service.oab.redirect(res.url) if API.service.oab?
        break if res.url and res.redirect isnt false
  return res

API.use.doaj.articles.format = (rec, metadata={}) ->
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  try metadata.open ?= rec.open
  try metadata.redirect ?= rec.redirect
  try rec = rec.bibjson
  try metadata.title ?= rec.title
  try metadata.abstract ?= rec.abstract.replace(/\n/g,' ')
  try metadata.volume ?= rec.journal.volume
  try metadata.issn ?= rec.journal.issns[0]
  if not metadata.page?
    try metadata.page = rec.start_page
    try metadata.page += '-' + rec.end_page if rec.end_page?
  try metadata.journal ?= rec.journal.title
  try metadata.publisher ?= rec.journal.publisher
  try metadata.year ?= rec.year
  try
    rm = rec.month ? '01'
    rm = 1 if rm is 0 or rm is "0"
    if rec.month?
      try
        rmt = rec.month.substring(0,3).toLowerCase()
        if rmt.length is 3
          idx = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf rmt
          rm = idx+1 if idx isnt -1
    metadata.published ?= rec.year + '-' + rm + '-' + (rec.day ? '01')
  try
    metadata.author ?= []
    for a in rec.author
      as = a.name.split(' ')
      a.family = as[as.length-1]
      a.given = a.name.replace(a.family,'').trim()
      if a.affiliation?
        a.affiliation = a.affiliation[0] if _.isArray a.affiliation
        a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
      metadata.author.push a
  try
    metadata.keyword ?= []
    metadata.keyword.push(s.term) for s in rec.subject
  try
    for id in rec.identifier
      if id.type.toLowerCase() is 'doi'
        metadata.doi ?= id.id
        break
  try
    for l in rec.journal.license
      if l.open_access or not metadata.licence? or metadata.licence.indexOf('cc') isnt 0
        metadata.licence ?= l.type
        if l.open_access and not metadata.url?
          try
            for l in rec.link
              if l.type is 'fulltext'
                metadata.url = l.url
          metadata.url ?= 'https://doi.org/' + metadata.doi if metadata.doi?
          break
  return metadata  



API.use.doaj.status = () ->
  try
    return true if HTTP.call 'GET', 'https://doaj.org/api/v1/search/articles/_search', {timeout: API.settings.use?.doaj?.timeout ? API.settings.use?._timeout ? 2000}
  catch err
    return err.toString()

API.use.doaj.test = (verbose) ->
  console.log('Starting doaj test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call('GET', 'https://doaj.org/api/v1/search/articles/doi:10.1186/1758-2946-3-47')
      result.record = result.record.data.results[0] if result.record?.data?.results?
      delete result.record.last_updated # remove things that could change for good reason
      delete result.record.created_date
      return false if not result.record.bibjson.subject?
      delete result.record.bibjson.subject
      return _.isEqual result.record, API.use.doaj.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending doaj test') if API.settings.dev

  return result



API.use.doaj.test._examples = {
  record: {
    "id": "616925712973412d8c8678b40269dfe5",
    "bibjson": {
      "start_page": "47",
      "author": [
        {"name": "Jones Richard"},
        {"name": "MacGillivray Mark"},
        {"name": "Murray-Rust Peter"},
        {"name": "Pitman Jim"},
        {"name": "Sefton Peter"},
        {"name": "O'Steen Ben"},
        {"name": "Waites William"}
      ],
      "journal": {
        "publisher": "Springer",
        "language": ["EN"],
        "license": [
          {"url": "http://jcheminf.springeropen.com/submission-guidelines/copyright", "open_access": true, "type": "CC BY", "title": "CC BY"}
        ],
        "title": "Journal of Cheminformatics",
        "country": "GB",
        "number": "1",
        "volume": "3",
        "issns": ["1758-2946"]
      },
      "title": "Open Bibliography for Science, Technology, and Medicine",
      "month": "10",
      "link": [
        {"url": "http://www.jcheminf.com/content/3/1/47", "type": "fulltext"}
      ],
      "year": "2011",
      "identifier": [
        {"type": "doi", "id": "10.1186/1758-2946-3-47"},
        {"type": "pissn", "id": "1758-2946"}
      ],
      "abstract": "<p>Abstract</p> <p>The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought.</p> "
    }
  }
}

