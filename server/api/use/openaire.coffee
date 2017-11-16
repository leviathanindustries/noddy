
# http://api.openaire.eu

API.use ?= {}
API.use.openaire = {}

API.add 'use/openaire/search', get: () -> return API.use.openaire.search this.queryParams

API.add 'use/openaire/doi/:doipre/:doipost', get: () -> return API.use.openaire.doi this.urlParams.doipre + '/' + this.urlParams.doipost,this.queryParams.open


API.use.openaire.doi = (doi) ->
  return API.use.openaire.get {doi:doi}

API.use.openaire.title = (title) ->
  res = API.use.openaire.get {title:meta.title}

API.use.openaire.get = (params) ->
  res = API.cache.get params, 'openaire_get'
  if not res?
    res = API.use.openaire.search params
    rec = if typeof res.data isnt 'string' and res.data?.length > 0 then res.data[0] else undefined
    if rec?
      op = API.use.openaire.open rec, true
      rec.open = op.open
      rec.blacklist = op.blacklist
      API.cache.save params, 'openaire_get', rec
    return rec
  else
    return res
    
# openaire has a datasets endpoint too, but there appears to be no way to
# search it for datasets related to an article. Sometimes the users put
# the article title partially or completely in the description along with
# other info, but not always. So no good way to look for data related to an article yet

API.use.openaire.search = (params) ->
  url = 'http://api.openaire.eu/search/publications?format=json&OA=true&'
  if params
    params.size ?= 10
    for op of params
      # openaire uses page and size for paging whereas we default to ES from and size,
      # so do a convenience coneversion of from
      if op is 'from'
        pg = 0 # openaire is page indexed from 1, but if there is no 1, we just don't give a page url
        pg = if params.size is 0 then (params.from / 10) + 1 else (params.from / params.size) + 1
        url += 'page=' + pg + '&' if pg
      else
        url += op + '=' + params[op] + '&'
  API.log 'Using openaire for ' + url
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      results = []
      try results = if res.data.response.header.total.$ is 1 then [res.data.response.results.result] else res.data.response.results.result
      return { data: results, total: res.data.response.header.total.$}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', data: 'openaire API error', error: err}

API.use.openaire.open = (record,blacklist) ->
  res = {}
  if record.metadata?['oaf:result']?.bestlicense?['@classid'] is 'OPEN' and record.metadata['oaf:result'].children?.instance?.length > 0
    for i in record.metadata['oaf:result'].children.instance
      if i.licence?['@classid'] is 'OPEN' and i.webresource?.url?.$
        res.open = i.webresource.url.$
        if res.open?
          try
            resolves = HTTP.call 'HEAD', res.open
          catch
            res.open = undefined
        res.blacklist = API.service.oab?.blacklist(res.open) if blacklist and res.open
        break if res.open and not res.blacklist
  return if blacklist then res else (if res.open then res.open else false)


###

sortBy
Select the sorting order: sortBy=field,[ascending|descending]

where field is one of: dateofcollection, resultstoragedate, resultstoragedate, resultembargoenddate, resultembargoendyear, resultdateofacceptance, resultacceptanceyear

doi
Gets the publications with the given DOIs, if any. Allowed values: comma separated list of DOIs. Alternatevely, it is possible to repeat the paramater for each requested doi.

openairePublicationID
Gets the publication with the given openaire identifier, if any. Allowed values: comma separated list of openaire identifiers. Alternatevely, it is possible to repeat the paramater for each requested identifier.

fromDateAccepted
Gets the publications whose date of acceptance is greater than or equal the given date. Allowed values: date formatted as YYYY-MM-DD.

toDateAccepted
Gets the publications whose date of acceptance is less than or equal the given date. Allowed values: date formatted as YYYY-MM-DD.

title
Gets the publications whose titles contain the given list of keywords. Allowed values: white-space separated list of keywords.

author
Search for publications by authors. Allowed value is a white-space separated list of names and/or surnames.

openaireAuthorID
Search for publications by openaire author identifier. Allowed values: comma separated list of identifiers. Alternatevely, it is possible to repeat the paramater for each author id. In both cases, author identifiers will form a query with OR semantics.

openaireProviderID
Search for publications by openaire data provider identifier. Allowed values: comma separated list of identifiers. Alternatevely, it is possible to repeat the paramater for each provider id. In both cases, provider identifiers will form a query with OR semantics.

openaireProjectID
Search for publications by openaire project identifier. Allowed values: comma separated list of identifiers. Alternatevely, it is possible to repeat the paramater for each provider id. In both cases, provider identifiers will form a query with OR semantics.

hasProject
Allowed values: true|false. If hasProject is true gets the publications that have a link to a project. If hasProject is false gets the publications with no links to projects.

projectID
Search for publications associated to a project with the given grant identifier.

FP7ProjectID
Search for publications associated to a FP7 project with the given grant number. It is equivalent to a query by funder=FP7&projectID=grantID

OA
Allowed values: true|false. If OA is true gets Open Access publications. If OA is false gets the non Open Access publications

###
