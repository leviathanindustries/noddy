

# a crossref API client
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

API.use ?= {}
API.use.crossref = {works:{}}

API.add 'use/crossref/works/doi/:doipre/:doipost',
  get: () -> return API.use.crossref.works.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.add 'use/crossref/works/search',
  get: () -> return API.use.crossref.works.search this.queryParams.q, this.queryParams.from, this.queryParams.size, this.queryParams.filter

API.add 'use/crossref/works/published/:startdate',
  get: () -> return API.use.crossref.works.published this.urlParams.startdate, undefined, this.queryParams.from, this.queryParams.size, this.queryParams.filter

API.add 'use/crossref/works/published/:startdate/:enddate',
  get: () -> return API.use.crossref.works.published this.urlParams.startdate, this.urlParams.enddate, this.queryParams.from, this.queryParams.size, this.queryParams.filter

API.add 'use/crossref/reverse',
  get: () -> return API.use.crossref.reverse [this.queryParams.q], this.queryParams.score
  post: () -> return API.use.crossref.reverse this.request.body

API.add 'use/crossref/resolve/:doipre/:doipost', get: () -> return API.use.crossref.resolve this.urlParams.doipre + '/' + this.urlParams.doipost
API.add 'use/crossref/resolve', get: () -> return API.use.crossref.resolve this.queryParams.doi


API.use.crossref.reverse = (citations,score=80) ->
  citations = [citations] if typeof citations is 'string'
  url = 'https://api.crossref.org/reverse'
  try
    res = HTTP.call 'POST', url, {data:citations}
    if res.statusCode is 200
      if res?.data?.message?.DOI and res.data.message.score and res.data.message.type is 'journal-article'
        sc = res.data.message.score
        if sc < score
          ignore = ["a","an","and","are","as","at","but","be","by","do","for","if","in","is","it","or","so","the","to"]
          titleparts = res.data.message.title[0].toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9]/g,' ').split(' ')
          titles = []
          titles.push(f) if ignore.indexOf(f.split("'")[0]) is -1 and f.length > 0 for f in titleparts
          citeparts = citations.join(' ').toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9]/g,' ').replace(/  /g,' ').split(' ')
          cites = []
          cites.push(c) if ignore.indexOf(c.split("'")[0]) is -1 and c.length > 1 for c in citeparts
          bonus = (score - sc)/titles.length + 1
          found = []
          found.push(w) if w in cites for w in titles
          sc += bonus * found.length if titles.length is found.length and found.join() is found.sort().join()
        if sc >= score
          return { data: {doi:res.data.message.DOI, title:res.data.message.title[0], received:res.data.message.score, adjusted: sc}, original:res.data}
        else
          return { data: {info: 'below score', received:res.data.message.score, adjusted: sc}, original:res.data}
      else
        return {}
    else
      return { status: 'error', data: res }
  catch err
    return { status: 'error', error: err.toString() }

API.use.crossref.resolve = (doi) ->
  doi = doi.replace('http://','').replace('https://','').replace('dx.doi.org/','').replace('doi.org/','')
  cached = API.http.cache doi, 'crossref_resolve'
  if cached
    return cached
  else
    url = false
    try
      # TODO NOTE that the URL given by crossref doi resolver may NOT be the final resolved URL. The publisher may still redirect to a different one
      resp = HTTP.call 'GET', 'https://doi.org/api/handles/' + doi
      for r in resp.data?.values
        if r.type.toLowerCase() is 'url'
          url = r.data.value
          # like these weird chinese ones, which end up throwing 404 anyway, but, just in case - https://doi.org/api/handles/10.7688/j.issn.1000-1646.2014.05.20
          url = new Buffer(url,'base64').toString('utf-8') if r.data.format is 'base64'
          API.http.cache doi, 'crossref_resolve', url
    return url

API.use.crossref.works.doi = (doi) ->
  url = 'https://api.crossref.org/works/' + doi
  API.log 'Using crossref for ' + url
  cached = API.http.cache doi, 'crossref_works_doi'
  if cached
    return cached
  else
    try
      res = HTTP.call 'GET', url
      if res.statusCode is 200
        API.http.cache doi, 'crossref_works_doi', res.data.message
        return res.data.message
      else
        return undefined
    catch
      return undefined

API.use.crossref.works.search = (qrystr,from,size,filter) ->
  url = 'https://api.crossref.org/works?';
  if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'').replace(/ AND /g,'+').replace(/ OR /g,' ').replace(/ NOT /g,'-').replace(/ /g,'+')
    url += 'query=' + qry
  url += '&offset=' + from if from?
  url += '&rows=' + size if size?
  url += '&filter=' + filter if filter?
  url = url.replace('?&','?') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  API.log 'Using crossref for ' + url
  res = HTTP.call 'GET', url
  return if res.statusCode is 200 then { total: res.data.message['total-results'], data: res.data.message.items, facets: res.data.message.facets} else { status: 'error', data: res}

API.use.crossref.works.published = (startdate,enddate,from,size,filter) ->
  # using ?filter=from-pub-date:2004-04-04,until-pub-date:2004-04-04 (the dates are inclusive)
  if filter? then filter += ',' else filter = ''
  filter += 'from-pub-date:' + startdate
  filter += ',until-pub-date:' + enddate if enddate
  return API.use.crossref.works.search undefined, from, size, filter

API.use.crossref.works.indexed = (startdate,enddate,from,size,filter) ->
  if filter? then filter += ',' else filter = ''
  filter += 'from-index-date:' + startdate
  filter += ',until-index-date:' + enddate if enddate
  return API.use.crossref.works.search undefined, from, size, filter



API.use.crossref.status = () ->
  try
    res = HTTP.call 'GET', 'https://api.crossref.org/works/10.1186/1758-2946-3-47', {timeout: API.settings.use?.crossref?.timeout ? API.settings.use?._timeout ? 4000}
    return if res.statusCode is 200 and res.data.status is 'ok' then true else res.data
  catch err
    return err.toString()

API.use.crossref.test = (verbose) ->
  console.log('Starting crossref test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call 'GET', 'https://api.crossref.org/works/10.1186/1758-2946-3-47'
      if result.record.data?
        result.record = result.record.data.message
        delete result.record.indexed # remove some stuff that is irrelevant to the match
        delete result.record['reference-count']
        delete result.record['is-referenced-by-count']
        delete result.record['references-count']
      return _.isEqual result.record, API.use.crossref.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending crossref test') if API.settings.dev

  return result

API.use.crossref.test._examples = {
  record: {
    "publisher": "Springer Nature",
    "issue": "1",
    "content-domain": {
      "domain": [],
      "crossmark-restriction": false
    },
    "short-container-title": [
      "Journal of Cheminformatics",
      "J Cheminf"
    ],
    "published-print": {
      "date-parts": [
        [
          2011
        ]
      ]
    },
    "DOI": "10.1186/1758-2946-3-47",
    "type": "journal-article",
    "created": {
      "date-parts": [
        [
          2011,
          11,
          1
        ]
      ],
      "date-time": "2011-11-01T20:17:30Z",
      "timestamp": 1320178650000
    },
    "page": "47",
    "source": "Crossref",
    "title": [
      "Open Bibliography for Science, Technology, and Medicine"
    ],
    "prefix": "10.1186",
    "volume": "3",
    "author": [
      {
        "given": "Richard",
        "family": "Jones",
        "affiliation": []
      },
      {
        "given": "Mark",
        "family": "MacGillivray",
        "affiliation": []
      },
      {
        "given": "Peter",
        "family": "Murray-Rust",
        "affiliation": []
      },
      {
        "given": "Jim",
        "family": "Pitman",
        "affiliation": []
      },
      {
        "given": "Peter",
        "family": "Sefton",
        "affiliation": []
      },
      {
        "given": "Ben",
        "family": "O'Steen",
        "affiliation": []
      },
      {
        "given": "William",
        "family": "Waites",
        "affiliation": []
      }
    ],
    "member": "297",
    "container-title": [
      "Journal of Cheminformatics"
    ],
    "original-title": [],
    "deposited": {
      "date-parts": [
        [
          2016,
          5,
          16
        ]
      ],
      "date-time": "2016-05-16T17:48:02Z",
      "timestamp": 1463420882000
    },
    "score": 1,
    "subtitle": [],
    "short-title": [],
    "issued": {
      "date-parts": [
        [
          2011
        ]
      ]
    },
    "alternative-id": [
      "1758-2946-3-47"
    ],
    "URL": "http://dx.doi.org/10.1186/1758-2946-3-47",
    "relation": {},
    "ISSN": [
      "1758-2946"
    ],
    "issn-type": [
      {
        "value": "1758-2946",
        "type": "print"
      }
    ],
    "subject": [
      "Physical and Theoretical Chemistry",
      "Library and Information Sciences",
      "Computer Graphics and Computer-Aided Design",
      "Computer Science Applications"
    ]
  }
}


