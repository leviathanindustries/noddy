

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
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  return API.use.core.get 'title:"' + title + '"'

API.use.core.get = (qrystr) ->
  res = API.http.cache qrystr, 'core_get'
  if not res?
    ret = API.use.core.search qrystr
    if ret.total
      res = ret.data[0]
      for i in ret.data
        if i.hasFullText is "true"
          res = i
          break
  if res?
    op = API.use.core.redirect res
    res.url = op.url
    res.redirect = op.redirect
    API.http.cache qrystr, 'core_get', res
  return res

API.use.core.search = (qrystr,from,size=10,timeout=API.settings.use?.core?.timeout ? API.settings.use?._timeout ? 10000) ->
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
    res = HTTP.call 'GET', url, {timeout:timeout}
    return if res.statusCode is 200 then { total: res.data.totalHits, data: res.data.data} else { status: 'error', data: res}
  catch err
    return {status: 'error', error: err.toString()}

API.use.core.redirect = (record) ->
  res = {}
  if record.fulltextIdentifier
    res.url = record.fulltextIdentifier
    if res.url.indexOf('core.ac.uk') is -1 and API.service.oab?
      res.redirect = API.service.oab.redirect(record.fulltextIdentifier)
  if res.redirect is false
    for u in record.fulltextUrls
      if u.indexOf('core.ac.uk') isnt -1
        res.url = u # no need to redirect, links in core are open
        break
      else
        resolved = API.http.resolve u
        if resolved and resolved.indexOf('.pdf') isnt -1
          # no good way to know if a resolved URL can actually be accessed, so only use it if it seems to be a pdf (which is usually accessible)
          res.url = resolved
          res.redirect = API.service.oab.redirect(res.url) if res.url? and API.service.oab?
          break if res.redirect isnt false
  return res



API.use.core.status = () ->
  s = API.use.core.search('doi:"10.1186/1758-2946-3-47"')
  return if s.status isnt 'error' then true else s.error

API.use.core.test = (verbose) ->
  console.log('Starting core test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = API.use.core.search 'doi:"10.1186/1758-2946-3-47"'
      result.record = result.record.data[0] if result.record.total
      try
        # simplify the repos because they do sometimes return internal metadata that does not indicate failure but would not match
        result.record.repositories = [{id:result.record.repositories[0].id,openDoarId:result.record.repositories[0].openDoarId,name:result.record.repositories[0].name}]
      return _.isEqual result.record, API.use.core.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending core test') if API.settings.dev

  return result

API.use.core.test._examples = {
  record: {
    "id": "81869340",
    "authors": [
      "Richard Jones",
      "Mark MacGillivray",
      "Peter Murray-Rust",
      "Jim Pitman",
      "Peter Sefton",
      "Ben O'Steen",
      "William Waites"
    ],
    "contributors": [],
    "datePublished": "2011",
    "identifiers": [
      "10.1186/1758-2946-3-47"
    ],
    "publisher": "Springer Nature",
    "relations": [
      "http://dx.doi.org/10.1186/1758-2946-3-47"
    ],
    "repositories": [
      {
        "id": "2612",
        "openDoarId": 0,
        "name": "Springer - Publisher Connector",
      }
    ],
    "subjects": [
      "journal-article"
    ],
    "title": "Open Bibliography for Science, Technology, and Medicine",
    "topics": [],
    "types": [],
    "year": 2011,
    "fulltextUrls": [
      "https://core.ac.uk/download/pdf/81869340.pdf",
      "https://core.ac.uk/display/81869340"
    ],
    "fulltextIdentifier": "https://core.ac.uk/download/pdf/81869340.pdf",
    "doi": "10.1186/1758-2946-3-47",
    "downloadUrl": "https://core.ac.uk/download/pdf/81869340.pdf"
  }
}



