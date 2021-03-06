

# BASE provide a search endpoint, but must register our IP to use it first
# limited to non-commercial and 1 query per second, contact them for more options
# register here: https://www.base-search.net/about/en/contact.php (registered)
# docs here:
# http://www.base-search.net/about/download/base_interface.pdf

API.use ?= {}
API.use.base = {}

API.add 'use/base/search', get: () -> return API.use.base.search this.queryParams.q, this.queryParams.from, this.queryParams.size, this.queryParams.format?

API.add 'use/base/title/:qry', get: () -> return API.use.base.title this.urlParams.qry

API.add 'use/base/doi/:doipre/:doipost', get: () -> return API.use.base.doi this.urlParams.doipre+'/'+this.urlParams.doipost, this.queryParams.format?


API.use.base.doi = (doi,format) ->
	# TODO should simplify response down to just one result if possible
	# TODO should consider deref via crossref then doing title search on BASE instead, if not found by DOI
	# e.g. 10.1016/j.biombioe.2012.01.022 can be found in BASE with title but not with DOI
	# also note when simplifying title that titles from crossref can include xml in them
	# like https://dev.api.cottagelabs.com/use/crossref/works/doi/10.1016/j.cpc.2016.07.035
	# which has mathml in the title, perhaps put there by the publisher and not stripped by crossref, or put there by crossref
	res = API.use.base.get doi
	return if format then API.use.base.format(res) else res

API.use.base.title = (title) ->
  simplify = /[\u0300-\u036F]/g
  title = title.toLowerCase().normalize('NFKD').replace(simplify,'').replace(/ß/g,'ss')
  ret = API.use.base.get('dctitle:"'+title+'"')
  if ret?.dctitle? or ret.title?
    ret.title ?= ret.dctitle
    if ret.title
      ct = ret.title.toLowerCase().normalize('NFKD').replace(simplify,'').replace(/ß/g,'ss')
      if ct and ct.length <= title.length*1.2 and ct.length >= title.length*.8 and title.replace(/ /g,'').indexOf(ct.replace(' ','').replace(' ','').replace(' ','').split(' ')[0]) isnt -1
        return ret
  return undefined

API.use.base.get = (qry) ->
	res = API.http.cache qry, 'base_get'
	if not res?
		res = API.use.base.search qry
		res = if res?.docs?.length then res.docs[0] else undefined
		if res?
			res.url = API.http.resolve res.dclink
			API.http.cache qry, 'base_get', res
	res.redirect = API.service.oab.redirect(res.url) if res?.url? and API.service.oab?
	return res

API.use.base.search = (qry='*', from, size, format, timeout=API.settings.use?.base?.timeout ? API.settings.use?._timeout ? 5000) ->
  # it uses offset and hits (default 10) for from and size, and accepts solr query syntax
  # string terms, "" to be next to each other, otherwise ANDed, can accept OR, and * or ? wildcards, brackets to group, - to negate
  proxy = API.settings.proxy # need to route through the proxy so requests come from registered IP
  if not proxy
    API.log 'No proxy settings available to use BASE'
    return { status: 'error', data: 'NO BASE PROXY SETTING PRESENT!', error: 'NO BASE PROXY SETTING PRESENT!'}
  qry = qry.replace(/ /g,'+') if qry.indexOf('"') is -1 and qry.indexOf(' ') isnt -1
  url = 'https://api.base-search.net/cgi-bin/BaseHttpSearchInterface.fcgi?func=PerformSearch&format=json&query=' + qry
  url += '&offset=' + from if from # max 1000
  url += '&hits=' + size if size # max 125
  url += '&sortBy=dcdate+desc'
  API.log 'Using BASE for ' + url
  try
    res = HTTP.call 'GET', url, {timeout:timeout,npmRequestOptions:{proxy:proxy}}
    if res.statusCode is 200
      res = JSON.parse(res.content).response
      if format
        for d of res.docs
          res.docs[d] = API.use.base.format res.docs[d]
      res.data = res.docs
      delete res.docs
      res.total = res.numFound
      return res
    else
      return res
  catch err
    return { status: 'error', data: 'BASE API error', error: err.toString()}

API.use.base.format = (rec, metadata={}) ->
  try metadata.title ?= rec.dctitle
  try metadata.doi ?= rec.dcdoi[0]
  try
    metadata.author ?= []
    for a in rec[if rec.dcperson? then 'dcperson' else 'dccreator']
      as = a.split(' ')
      ar = {name: a, given:as[as.length-1]}
      try ar.family = as[0]
      metadata.author.push ar
  try metadata.journal ?= rec.dcsource.split(',')[0]
  try metadata.volume ?= rec.dcsource.toLowerCase().split('vol')[1].split(',')[0].trim()
  try metadata.issue ?= rec.dcsource.toLowerCase().split('iss')[1].split(',')[0].trim()
  try metadata.page ?= rec.dcsource.toLowerCase().split('iss')[1].split('p')[1].split('(')[0].trim()
  try metadata.year ?= rec.dcyear
  try metadata.published ?= rec.dcdate.split('T')[0]
  try
    if metadata.year and not metadata.published
      metadata.published = metadata.year + '-01-01'
  try metadata.publisher ?= rec.dcpublisher[0]
  try
    for id in rec.dcrelation
      if id.length is 9 and id.indexOf('-') is 4
        meta.issn ?= id
        break
  try metadata.keyword ?= rec.dcsubject
  try metadata.abstract ?= rec.dcdescription.replace('Abstract ','')
  try metadata.url ?= rec.dclink
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  try metadata.redirect ?= rec.redirect
  return metadata



API.use.base.status = () ->
  res = API.use.base.search()
  return if res.status isnt 'error' then true else res.error

API.use.base.test = (verbose) ->
  console.log('Starting base test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = API.use.base.search('10.1186/1758-2946-3-47').docs[0]
      return _.isEqual result.record, API.use.base.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending base test') if API.settings.dev

  return result

API.use.base.test._examples = {
  record: {
    "dcdate": "2011-10-01T00:00:00Z",
    "dcpublisher": [
      "Springer"
    ],
    "dcdescription": "Abstract The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought.",
    "dcyear": 2011,
    "dccountry": "org",
    "dcprovider": "Directory of Open Access Journals: DOAJ Articles",
    "dcdocid": "e5707b6f0ea794bd087e5d8f89f2445f1984512d30d84652840e2344fc57b421",
    "dcperson": [
      "Jones Richard",
      "MacGillivray Mark",
      "Murray-Rust Peter",
      "Pitman Jim",
      "Sefton Peter",
      "O'Steen Ben",
      "Waites William"
    ],
    "dcidentifier": [
      "https://doi.org/10.1186/1758-2946-3-47",
      "https://doaj.org/article/616925712973412d8c8678b40269dfe5"
    ],
    "dccontinent": "cww",
    "dclink": "https://doi.org/10.1186/1758-2946-3-47",
    "dctitle": "Open Bibliography for Science, Technology, and Medicine",
    "dcrelation": [
      "http://www.jcheminf.com/content/3/1/47",
      "https://doaj.org/toc/1758-2946"
    ],
    "dcdoi": [
      "10.1186/1758-2946-3-47"
    ],
    "dclanguage": [
      "EN"
    ],
    "dccreator": [
      "Jones Richard",
      "MacGillivray Mark",
      "Murray-Rust Peter",
      "Pitman Jim",
      "Sefton Peter",
      "O'Steen Ben",
      "Waites William"
    ],
    "dcsubject": [
      "Chemistry",
      "QD1-999",
      "Science",
      "Q",
      "DOAJ:Chemistry (General)",
      "DOAJ:Chemistry",
      "Information technology",
      "T58.5-58.64"
    ],
    "dclang": [
      "eng"
    ],
    "dccollection": "ftdoajarticles",
    "dcoa": 1,
    "dchdate": "2017-09-23T17:42:24Z",
    "dctype": [
      "article"
    ],
    "dcsource": "Journal of Cheminformatics, Vol 3, Iss 1, p 47 (2011)",
    "dctypenorm": [
      "121"
    ]
  }
}