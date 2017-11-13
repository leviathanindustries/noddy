
# Europe PMC client
# https://europepmc.org/RestfulWebService
# http://www.ebi.ac.uk/europepmc/webservices/rest/search/
# https://europepmc.org/Help#fieldsearch

# GET http://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:10.1007/bf00197367&resulttype=core&format=json
# default page is 1 and default pageSize is 25
# resulttype lite is smaller, lacks so much metadata, no mesh, terms, etc
# open_access:y added to query will return only open access articles, and they will have fulltext xml available at a link like the following:
# http://www.ebi.ac.uk/europepmc/webservices/rest/PMC3257301/fullTextXML
# can also use HAS_PDF:y to get back ones where we should expect to be able to get a pdf, but it is not clear if those are OA and available via eupmc
# can ensure a DOI is available using HAS_DOI
# can search publication date via FIRST_PDATE:1995-02-01 or FIRST_PDATE:[2000-10-14 TO 2010-11-15] to get range

API.use ?= {}
API.use.europepmc = {}

API.add 'use/europepmc/doi/:doipre/:doipost',
  get: () -> return API.use.europepmc.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.add 'use/europepmc/pmid/:qry',
  get: () ->
    res = API.use.europepmc.pmid this.urlParams.qry
    try
      return res.data.resultList.result[0]
    catch
      return res.data

API.add 'use/europepmc/pmc/:qry',
  get: () ->
    res = API.use.europepmc.pmc this.urlParams.qry
    try
      return res.data.resultList.result[0]
    catch
      return res.data

API.add 'use/europepmc/pmc/:qry/fulltext',
  get: () ->
    if 404 is ft = API.use.europepmc.fulltextXML this.urlParams.qry
      return 404
    else
      this.response.writeHead 200,
        'Content-type': 'application/xml'
        'Content-length': ft.length
      this.response.end ft
      this.done()

API.add 'use/europepmc/pmc/:qry/licence', get: () -> return API.use.europepmc.licence this.urlParams.qry

API.add 'use/europepmc/pmc/:qry/aam', get: () -> return API.use.europepmc.authorManuscript this.urlParams.qry

API.add 'use/europepmc/search/:qry',
  get: () -> return API.use.europepmc.search this.urlParams.qry, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/published/:startdate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, undefined, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/published/:startdate/:enddate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, this.urlParams.enddate, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/indexed/:startdate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, undefined, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/indexed/:startdate/:enddate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, this.urlParams.enddate, this.queryParams.from, this.queryParams.size

API.use.europepmc.doi = (doi) ->
  res = API.use.europepmc.search 'DOI:' + doi
  return if res.total > 0 then res.data[0] else res

API.use.europepmc.pmid = (ident) ->
  res = API.use.europepmc.search 'EXT_ID:' + ident + ' AND SRC:MED'
  return if res.total > 0 then res.data[0] else res

API.use.europepmc.pmc = (ident) ->
  res = API.use.europepmc.search 'PMCID:PMC' + ident.toLowerCase().replace('pmc','')
  return if res.total > 0 then res.data[0] else res

API.use.europepmc.search = (qrystr,from,size) ->
  # TODO epmc changed to using a cursormark for pagination, so change how we pass paging to them
  # see https://github.com/CottageLabs/LanternPM/issues/124
  url = 'http://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '&resulttype=core&format=json'
  url += '&pageSize=' + size if size?
  url += '&page=' + (Math.floor(from/size)+1) if from?
  API.log 'Using eupmc for ' + url
  res
  try
    res = HTTP.call 'GET',url
  ret = {}
  if res?.data?.hitCount
    ret.total = res.data.hitCount;
    ret.data = if res.data?.resultList then res.data.resultList.result else []
  else
    ret.status = 'error'
    ret.total = 0
  return ret

API.use.europepmc.open = (res) ->
  if typeof res isnt 'object'
    if res.indexOf('10.') is 0
      res = API.use.europepmc.doi res
    else
      res = API.use.europepmc.search res
      res.data = res.data?[0]
  if res?.fullTextUrlList?.fullTextUrl?
    for oi in res.fullTextUrlList.fullTextUrl
      # we only accepted oa and html previously - TODO find out why, and if we have to be so strict for a reason
      if oi.availabilityCode.toLowerCase() in ['oa','f'] and oi.documentStyle.toLowerCase() in ['pdf','html']
        return oi.url
  return false

# http://dev.api.cottagelabs.com/use/europepmc/search/has_doi:n%20AND%20FIRST_PDATE:[2016-03-22%20TO%202016-03-22]
API.use.europepmc.published = (startdate,enddate,from,size,qrystr='') ->
  qrystr += ' AND '
  if enddate
    qrystr += 'FIRST_PDATE:[' + startdate + ' TO ' + enddate + ']'
  else
    qrystr += 'FIRST_PDATE:' + startdate
  url = 'http://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '&resulttype=core&format=json'
  url += '&pageSize=' + size if size?
  url += '&page=' + (Math.floor(from/size)+1) if from?
  API.log 'Using eupmc for ' + url
  try
    res = HTTP.call 'GET', url
    return { total: res.data.hitCount, data: res.data.resultList.result}
  catch
    return { status: 'error', total: 0}

API.use.europepmc.indexed = (startdate,enddate,from,size,qrystr='') ->
  qrystr += ' AND '
  if enddate
    qrystr += 'CREATION_DATE:[' + startdate + ' TO ' + enddate + ']'
  else
    qrystr += 'CREATION_DATE:' + startdate
  url = 'http://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '&resulttype=core&format=json'
  url += '&pageSize=' + size if size?
  url += '&page=' + (Math.floor(from/size)+1) if from?
  API.log 'Using eupmc for ' + url
  try
    res = HTTP.call 'GET',url
    return { total: res.data.hitCount, data: res.data.resultList.result}
  catch
    return { status: 'error', total: 0}

API.use.europepmc.licence = (pmcid,rec,fulltext,noui) ->
  API.log msg: 'Europemc licence checking', pmcid: pmcid, rec: rec?, fulltext: fulltext?, noui: noui
  maybe_licence
  res = API.use.europepmc.search('PMC' + pmcid.toLowerCase().replace('pmc','')) if pmcid and not rec
  if res?.total > 0 or rec or fulltext
    rec ?= res.data[0]
    pmcid = rec.pmcid if not pmcid and rec
    fulltext = API.use.europepmc.fulltextXML(pmcid) if not fulltext and pmcid
    if fulltext isnt 404 and typeof fulltext is 'string' and fulltext.indexOf('<') is 0
      licinperms = API.service.lantern.licence undefined,undefined,fulltext,'<permissions>','</permissions>'
      if licinperms.licence?
        licinperms.source = 'epmc_xml_permissions'
        return licinperms

      licanywhere = API.service.lantern.licence undefined,undefined,fulltext
      if licanywhere.licence?
        licanywhere.source = 'epmc_xml_outside_permissions'
        return licanywhere

      if fulltext.indexOf('<permissions>') isnt -1
        maybe_licence = {licence:'non-standard-licence',source:'epmc_xml_permissions'}

    if pmcid and not noui
      normalised_pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc','')
      licsplash = API.job.limit(10000,'API.service.lantern.licence',['http://europepmc.org/articles/' + normalised_pmcid],'EPMCUI')
      if licsplash.licence?
        licsplash.source = 'epmc_html'
        return licsplash

    return maybe_licence ? false
  else
    return false

API.use.europepmc.authorManuscript = (pmcid,rec,fulltext,noui) ->
  if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
    return {aam:true,info:'fulltext'}
  else
    # if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    #rec = API.use.europepmc.search('PMC' + pmcid.toLowerCase().replace('pmc',''))?.data?[0] if pmcid and not rec
    pmcid ?= rec?.pmcid
    if pmcid
      fulltext = API.use.europepmc.fulltextXML pmcid
      if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
        return {aam:true,info:'fulltext'}
      else if not noui
        url = 'http://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
        try
          pg = API.job.limit(10000,'HTTP.call',['GET',url],"EPMCUI")
          if pg?.statusCode is 200
            page = pg.content
            s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal'
            s2 = 'Author manuscript; available in PMC'
            s3 = 'logo-nihpa.gif'
            s4 = 'logo-wtpa2.gif'
            if page.indexOf(s1) isnt -1 or page.indexOf(s2) isnt -1 or page.indexOf(s3) isnt -1 or page.indexOf(s4) isnt -1
              return {aam:true,info:'splashpage'}
        catch err
          if err.response?.statusCode is 404
            return {aam:false,info:'not in EPMC (404)'}
          else if err.response?.statusCode is 403 and err.response?.content?.indexOf('block access') is 0
            API.log 'EPMC blocking us'
            return {info: 'EPMC blocking access, AAM status unknown'}
          else
            return {info:'Unknown error accessing EPMC', error: err.toString(), code: err.response?.statusCode}
  return {aam:false}

API.use.europepmc.fulltextXML = (pmcid) ->
  pmcid = pmcid.toLowerCase().replace('pmc','') if pmcid
  url = 'http://www.ebi.ac.uk/europepmc/webservices/rest/PMC' + pmcid + '/fullTextXML'
  try
    r = HTTP.call 'GET', url
    return if r.statusCode is 200 then r.content else undefined
  catch err
    return if err.response?.statusCode is 404 then err.response.statusCode else err.toString()

