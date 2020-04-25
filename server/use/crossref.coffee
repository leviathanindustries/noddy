

# a crossref API client
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

# crossref now prefers some identifying headers
header = {
  'User-Agent': (API.settings.name ? 'noddy') + ' v' + (API.settings.version ? '0.0.1') + (if API.settings.dev then 'd' else '') + ' (https://cottagelabs.com; mailto:' + API.settings.log?.to ? 'mark@cottagelabs.com' + ')'
}

API.use ?= {}
API.use.crossref = {works:{},journals:{}}

API.add 'use/crossref/works/doi/:doipre/:doipost',
  get: () -> return API.use.crossref.works.doi this.urlParams.doipre + '/' + this.urlParams.doipost, this.queryParams.format?
# there are DOIs that can have slashes within their second part and are valid. Possibly could have more than one slash
# and there does not seem to be a way to pass wildcards to the urlparams to match multiple / routes
# so this will do for now...
API.add 'use/crossref/works/doi/:doipre/:doipost/:doimore',
  get: () -> return API.use.crossref.works.doi this.urlParams.doipre + '/' + this.urlParams.doipost + '/' + this.urlParams.doimore, this.queryParams.format?

API.add 'use/crossref/works',
  get: () -> return API.use.crossref.works.search (this.queryParams.q ? this.queryParams.query), (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.sort, this.queryParams.order, this.queryParams.format?
API.add 'use/crossref/works/search',
  get: () -> return API.use.crossref.works.search (this.queryParams.q ? this.queryParams.query), (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.sort, this.queryParams.order, this.queryParams.format?

API.add 'use/crossref/works/published',
  get: () -> return API.use.crossref.works.published (this.queryParams.q ? this.queryParams.query), undefined, undefined, (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format?
API.add 'use/crossref/works/published/:startdate',
  get: () -> return API.use.crossref.works.published (this.queryParams.q ? this.queryParams.query), this.urlParams.startdate, undefined, (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format?
API.add 'use/crossref/works/published/:startdate/:enddate',
  get: () -> return API.use.crossref.works.published (this.queryParams.q ? this.queryParams.query), this.urlParams.startdate, this.urlParams.enddate, (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format?

API.add 'use/crossref/works/indexed',
  get: () -> return API.use.crossref.works.indexed (this.queryParams.q ? this.queryParams.query), undefined, undefined, (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format?
API.add 'use/crossref/works/indexed/:startdate',
  get: () -> return API.use.crossref.works.indexed (this.queryParams.q ? this.queryParams.query), this.urlParams.startdate, undefined, (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format?
API.add 'use/crossref/works/indexed/:startdate/:enddate',
  get: () -> return API.use.crossref.works.indexed (this.queryParams.q ? this.queryParams.query), this.urlParams.startdate, this.urlParams.enddate, (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format?

API.add 'use/crossref/types',
  get: () -> return API.use.crossref.types()

API.add 'use/crossref/journals',
  get: () -> return API.use.crossref.journals.search (this.queryParams.q ? this.queryParams.query), (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter
API.add 'use/crossref/journals/search',
  get: () -> return API.use.crossref.journals.search (this.queryParams.q ? this.queryParams.query), (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter

API.add 'use/crossref/journals/:issn',
  get: () -> return API.use.crossref.journals.issn this.urlParams.issn

API.add 'use/crossref/journals/:issn/works',
  get: () -> return API.use.crossref.journals.works this.urlParams.issn

API.add 'use/crossref/journals/:issn/works/dois',
  get: () -> return API.use.crossref.journals.dois this.urlParams.issn

API.add 'use/crossref/reverse',
  get: () -> return API.use.crossref.reverse [this.queryParams.q ? this.queryParams.query ? this.queryParams.title], this.queryParams.score
  post: () -> return API.use.crossref.reverse this.request.body

API.add 'use/crossref/resolve/:doipre/:doipost', get: () -> return API.use.crossref.resolve this.urlParams.doipre + '/' + this.urlParams.doipost
API.add 'use/crossref/resolve', get: () -> return API.use.crossref.resolve this.queryParams.doi



API.use.crossref.types = () ->
  url = 'https://api.crossref.org/types'
  API.log 'Using crossref for ' + url
  try
    res = HTTP.call 'GET', url, {headers: header}
    if res.statusCode is 200
      return res.data.message.items
    else
      return undefined

API.use.crossref.reverse = (citations,score=80,format=false) ->
  citations = [citations] if typeof citations is 'string'
  url = 'https://api.crossref.org/reverse'
  API.log 'Using crossref for ' + url + ' with citation ' + JSON.stringify citations
  try
    res = HTTP.call 'POST', url, {data:citations, headers: header}
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
          if format
            return API.use.crossref.works.format res.data.message
          else
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
      resp = HTTP.call 'GET', 'https://doi.org/api/handles/' + doi, {headers: header}
      for r in resp.data?.values
        if r.type.toLowerCase() is 'url'
          url = r.data.value
          # like these weird chinese ones, which end up throwing 404 anyway, but, just in case - https://doi.org/api/handles/10.7688/j.issn.1000-1646.2014.05.20
          url = new Buffer(url,'base64').toString('utf-8') if r.data.format is 'base64'
          API.http.cache doi, 'crossref_resolve', url
    return url



API.use.crossref.journals.issn = (issn) ->
  url = 'https://api.crossref.org/journals/' + issn
  API.log 'Using crossref for ' + url
  cached = API.http.cache issn, 'crossref_journals_issn'
  if cached
    return cached
  else
    try
      res = HTTP.call 'GET', url, {headers: header}
      if res.statusCode is 200
        API.http.cache issn, 'crossref_journals_issn', res.data.message
        return res.data.message
      else
        return undefined
    catch
      return undefined

API.use.crossref.journals.works = (issn,from,size=100) ->
  # cannot cache this because list of works for a journal changes over time
  # could add time constrained caching, but not possible right now
  url = 'https://api.crossref.org/journals/' + issn + '/works?sort=published&order=desc&rows=' + size + (if from then '&from=' + from else '')
  API.log 'Using crossref for ' + url
  try
    res = HTTP.call 'GET', url, {headers: header}
    if res.statusCode is 200
      return res.data.message
    else
      return undefined
  catch
    return undefined

API.use.crossref.journals.dois = (issn) ->
  try
    dois = []
    works = API.use.crossref.journals.works issn, undefined, 10000
    dois.push(w.DOI) for w in works.items
    total = works['total-results']
    counter = 0
    while counter < total
      counter += 10000
      works = API.use.crossref.journals.works issn, counter, 10000
      dois.push(w.DOI) for w in works.items
    return dois
  catch
    return undefined

API.use.crossref.journals.search = (qrystr,from,size,filter) ->
  url = 'https://api.crossref.org/journals?';
  if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'').replace(/ AND /g,'+').replace(/ OR /g,' ').replace(/ NOT /g,'-').replace(/ /g,'+')
    url += 'query=' + qry
  url += '&offset=' + from if from?
  url += '&rows=' + size if size?
  url += '&filter=' + filter if filter?
  url = url.replace('?&','?') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  API.log 'Using crossref for ' + url
  res = HTTP.call 'GET', url, {headers: header}
  return if res.statusCode is 200 then { total: res.data.message['total-results'], data: res.data.message.items, facets: res.data.message.facets} else { status: 'error', data: res}



API.use.crossref.works.doi = (doi,format) ->
  url = 'https://api.crossref.org/works/' + doi
  API.log 'Using crossref for ' + url
  if cached = API.http.cache doi, 'crossref_works_doi'
    return if format then API.use.crossref.works.format(cached) else cached
  else
    try
      res = HTTP.call 'GET', url, {headers: header}
      if res.statusCode is 200
        API.http.cache doi, 'crossref_works_doi', res.data.message
        return if format then API.use.crossref.works.format(res.data.message) else res.data.message
      else
        return undefined
    catch
      return undefined

API.use.crossref.works.search = (qrystr,from,size,filter,sort,order='desc',format) ->
  # max size is 1000
  url = 'https://api.crossref.org/works?'
  url += 'sort=' + sort + '&order=' + order + '&' if sort?
  if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'').replace(/ AND /g,'+').replace(/ OR /g,' ').replace(/ NOT /g,'-').replace(/ /g,'+')
    url += 'query=' + qry
  url += '&offset=' + from if from?
  url += '&rows=' + size if size?
  url += '&filter=' + filter if filter? and filter isnt ''
  url = url.replace('?&','?') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  API.log 'Using crossref for ' + url
  res = HTTP.call 'GET', url, {headers: header}
  if res.statusCode is 200
    ri = res.data.message.items
    if format
      for r of ri
        ri[r] = API.use.crossref.works.format ri[r]
    return { total: res.data.message['total-results'], data: ri, facets: res.data.message.facets}
  else
    return { status: 'error', data: res}

API.use.crossref.works.published = (qrystr,startdate,enddate,from,size,filter,order,format) ->
  # using ?filter=from-pub-date:2004-04-04,until-pub-date:2004-04-04 (the dates are inclusive)
  if filter? then filter += ',' else filter = ''
  filter += 'from-pub-date:' + startdate if startdate
  filter += ',until-pub-date:' + enddate if enddate
  return API.use.crossref.works.search qrystr, from, size, filter, 'published', order, format

API.use.crossref.works.indexed = (qrystr,startdate,enddate,from,size,filter,order,format) ->
  if filter? then filter += ',' else filter = ''
  filter += 'from-index-date:' + startdate if startdate
  filter += ',until-index-date:' + enddate if enddate
  return API.use.crossref.works.search qrystr, from, size, filter, 'indexed', order, format

API.use.crossref.works.format = (rec, metadata={}) ->
  try metadata.title = rec.title[0]
  try metadata.doi = rec.DOI if rec.DOI?
  try metadata.doi = rec.doi if rec.doi? # just in case
  try metadata.crossref_type = rec.type
  try metadata.author = rec.author if rec.author?
  if metadata.author
    for a in metadata.author
      a.name = a.family + ' ' + a.given if not a.name? and a.family and a.given
      if a.affiliation?
        a.affiliation = a.affiliation[0] if _.isArray a.affiliation
        a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
        try a.affiliation.name = a.affiliation.name.replace(/\s\s+/g,' ').trim()
  try metadata.journal = rec['container-title'][0]
  try metadata.journal_short = rec['short-container-title'][0]
  try metadata.issue = rec.issue if rec.issue?
  try metadata.volume = rec.volume if rec.volume?
  try metadata.page = rec.page.toString() if rec.page?
  try metadata.issn = rec.ISSN[0]
  try metadata.keyword = rec.subject if rec.subject? # is a list of strings - goes in keywords because subject was already previously used as an object
  try metadata.publisher = rec.publisher if rec.publisher?
  for p in ['published-print','journal-issue.published-print','issued','published-online','created','deposited']
    try
      if rt = rec[p] ? rec['journal-issue']?[p.replace('journal-issue.','')]
        if typeof rt['date-time'] is 'string' and rt['date-time'].indexOf('T') isnt -1 and rt['date-time'].split('T')[0].split('-').length is 3
          metadata.published = rt['date-time'].split('T')[0]
          metadata.year = metadata.published.split('-')[0]
          break
        else if rt['date-parts']? and rt['date-parts'].length and _.isArray(rt['date-parts'][0]) and rt['date-parts'][0].length
          rp = rt['date-parts'][0]
          pbl = rp[0].toString()
          if pbl.length > 2 # needs to be a year
            metadata.year ?= pbl
            if rp.length is 1
              pbl += '-01-01'
            else
              m = false
              d = false
              if not isNaN(parseInt(rp[1])) and parseInt(rp[1]) > 12
                d = rp[1].toString()
              else
                m = rp[1].toString()
              if rp.length is 2
                if d isnt false
                  m = rp[2].toString()
                else
                  d = rp[2].toString()
              m = if m is false then '01' else if m.length is 1 then '0' + m else m
              d = if d is false then '01' else if d.length is 1 then '0' + d else d
              pbl += '-' + m + '-' + d
            metadata.published = pbl
            break
  try metadata.abstract = API.convert.html2txt(rec.abstract).replace(/\n/g,' ') if rec.abstract?
  try
    if rec.reference? and rec.reference.length
      metadata.reference ?= []
      for r in rec.reference
        rf = {}
        rf.doi = r.DOI if r.DOI?
        rf.title = r.article-title if r.article-title?
        rf.journal = r.journal-title if r.journal-title?
        metadata.reference.push(rf) if not _.isEmpty rf
  try
    if rec.license?
      for l in rec.license
        if typeof l.URL is 'string' and (typeof metadata.licence isnt 'string' or (metadata.licence.indexOf('creativecommons') is -1 and l.URL.indexOf('creativecommons') isnt -1))
          metadata.licence = l.URL
          if l.URL.indexOf('creativecommons') isnt -1
            md = 'https://doi.org/' + metadata.doi
            metadata.url ?= md
            metadata.url.push(md) if _.isArray(metadata.url) and md not in metadata.url
            try metadata.redirect = API.service.oab.redirect md
            break
  return metadata  



API.use.crossref.status = () ->
  try
    res = HTTP.call 'GET', 'https://api.crossref.org/works/10.1186/1758-2946-3-47', {headers: header, timeout: API.settings.use?.crossref?.timeout ? API.settings.use?._timeout ? 4000}
    return if res.statusCode is 200 and res.data.status is 'ok' then true else res.data
  catch err
    return err.toString()

API.use.crossref.test = (verbose) ->
  console.log('Starting crossref test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call 'GET', 'https://api.crossref.org/works/10.1186/1758-2946-3-47', {headers: header}
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


