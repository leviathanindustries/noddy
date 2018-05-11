

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
  return if r.results?.length then r.results[0] else 404

# title search possible with title:MY JOURNAL TITLE
API.use.doaj.journals.search = (qry,params) ->
  url = 'https://doaj.org/api/v1/search/journals/' + qry + '?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  res = HTTP.call 'GET', url
  return if res.statusCode is 200 then res.data else {status: 'error', data: res.data}

API.use.doaj.articles.doi = (doi) ->
  return API.use.doaj.articles.get 'doi:' + doi

API.use.doaj.articles.title = (title) ->
  return API.use.doaj.articles.get 'bibjson.title.exact:"' + title + '"'

API.use.doaj.articles.get = (qry) ->
  res = API.use.doaj.articles.search qry
  rec = if res?.results?.length then res.results[0] else undefined
  if rec?
    op = API.use.doaj.articles.redirect rec
    rec.url = op.url
    rec.redirect = op.redirect
  return rec

API.use.doaj.articles.search = (qry,params) ->
  url = 'https://doaj.org/api/v1/search/articles/' + qry + '?'
  url += op + '=' + params[op] + '&' for op of params
  API.log 'Using doaj for ' + url
  try
    res = HTTP.call 'GET', url
    return if res.statusCode is 200 then res.data else {status: 'error', data: res.data}
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

