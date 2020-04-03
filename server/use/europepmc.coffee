

# Europe PMC client
# https://europepmc.org/RestfulWebService
# https://www.ebi.ac.uk/europepmc/webservices/rest/search/
# https://europepmc.org/Help#fieldsearch

# GET https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:10.1007/bf00197367&resulttype=core&format=json
# default page is 1 and default pageSize is 25
# resulttype lite is smaller, lacks so much metadata, no mesh, terms, etc
# open_access:y added to query will return only open access articles, and they will have fulltext xml available at a link like the following:
# https://www.ebi.ac.uk/europepmc/webservices/rest/PMC3257301/fullTextXML
# can also use HAS_PDF:y to get back ones where we should expect to be able to get a pdf, but it is not clear if those are OA and available via eupmc
# can ensure a DOI is available using HAS_DOI
# can search publication date via FIRST_PDATE:1995-02-01 or FIRST_PDATE:[2000-10-14 TO 2010-11-15] to get range

API.use ?= {}
API.use.europepmc = {}

API.add 'use/europepmc/doi/:doipre/:doipost',
  get: () -> return API.use.europepmc.doi this.urlParams.doipre + '/' + this.urlParams.doipost
API.add 'use/europepmc/doi/:doipre/:doipost/:doimore',
  get: () -> return API.use.europepmc.doi this.urlParams.doipre + '/' + this.urlParams.doipost + '/' + this.urlParams.doimore

API.add 'use/europepmc/pmid/:qry', get: () -> return API.use.europepmc.pmid this.urlParams.qry

API.add 'use/europepmc/pmc/:qry', get: () -> return API.use.europepmc.pmc this.urlParams.qry

API.add 'use/europepmc/pmc/:qry/xml',
  get: () ->
    if 404 is ft = API.use.europepmc.xml this.urlParams.qry
      return 404
    else
      this.response.writeHead 200,
        'Content-type': 'application/xml'
        'Content-length': ft.length
      this.response.end ft

API.add 'use/europepmc/pmc/:qry/licence', get: () -> return API.use.europepmc.licence this.urlParams.qry

API.add 'use/europepmc/pmc/:qry/aam', get: () -> return API.use.europepmc.authorManuscript this.urlParams.qry

API.add 'use/europepmc/title/:qry', get: () -> return API.use.europepmc.title this.urlParams.qry

API.add 'use/europepmc/search/:qry',
  get: () -> return API.use.europepmc.search this.urlParams.qry, this.queryParams.from, this.queryParams.size, this.queryParams.format isnt 'false'

API.add 'use/europepmc/published/:startdate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, undefined, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/published/:startdate/:enddate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, this.urlParams.enddate, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/indexed/:startdate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, undefined, this.queryParams.from, this.queryParams.size

API.add 'use/europepmc/indexed/:startdate/:enddate',
  get: () -> return API.use.europepmc.published this.urlParams.startdate, this.urlParams.enddate, this.queryParams.from, this.queryParams.size

API.use.europepmc.doi = (doi,format) ->
  return API.use.europepmc.get 'DOI:' + doi, format

API.use.europepmc.pmid = (ident,format) ->
  return API.use.europepmc.get 'EXT_ID:' + ident + ' AND SRC:MED', format

API.use.europepmc.pmc = (ident,format) ->
  return API.use.europepmc.get 'PMCID:PMC' + ident.toLowerCase().replace('pmc',''), format

API.use.europepmc.title = (title,format) ->
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  return API.use.europepmc.get 'title:"' + title + '"', format

API.use.europepmc.get = (qrystr,format) ->
  res = API.http.cache qrystr, 'epmc_get'
  if not res?
    res = API.use.europepmc.search qrystr, undefined, undefined, format
    res = if res.total then res.data[0] else undefined
    if res?.fullTextUrlList?
      for oi in res.fullTextUrlList.fullTextUrl
        # we only accepted oa and html previously - TODO find out why, and if we have to be so strict for a reason
        if oi.availabilityCode.toLowerCase() in ['oa','f'] and oi.documentStyle.toLowerCase() in ['pdf','html']
          try
            resolves = HTTP.call 'HEAD', oi.url
            res.url = oi.url
            break
      API.http.cache qrystr, 'epmc_get', res
  return res

API.use.europepmc.search = (qrystr,from,size,format=true) ->
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '%20sort_date:y&resulttype=core&format=json'
  url += '&pageSize=' + size if size? #can handle 1000, have not tried more, docs do not say
  if from?
    if not isNaN parseInt from
      url += '&page=' + (Math.floor(from/size)+1) #old way, prob does not work any more
    else
      url += '&cursorMark=' + from
  API.log 'Using eupmc for ' + url
  try
    res = HTTP.call 'GET',url
  ret = {}
  if res?.data?.hitCount
    ret.total = res.data.hitCount
    ret.data = res.data.resultList?.result ? []
    ret.cursor = res.data.nextCursorMark
    if format
      for r of ret.data
        ret.data[r] = API.use.europepmc.format ret.data[r]
  else
    ret.status = 'error'
    ret.total = 0
  return ret


# example: search/has_doi:n%20AND%20FIRST_PDATE:[2016-03-22%20TO%202016-03-22]
API.use.europepmc.published = (startdate,enddate,from,size,qrystr='') ->
  qrystr += ' AND '
  if enddate
    qrystr += 'FIRST_PDATE:[' + startdate + ' TO ' + enddate + ']'
  else
    qrystr += 'FIRST_PDATE:' + startdate
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '&resulttype=core&format=json'
  url += '&pageSize=' + size if size?
  url += '&page=' + (Math.floor(from/size)+1) if from?
  API.log 'Using eupmc for ' + url
  try
    res = HTTP.call 'GET', url
    return { total: res.data.hitCount, data: res.data.resultList.result}
  catch
    return { status: 'error', total: 0}

API.use.europepmc.indexed = (qrystr='',startdate,enddate,from,size) ->
  qrystr += ' AND ' if qrystr isnt ''
  if enddate
    qrystr += 'CREATION_DATE:[' + startdate + ' TO ' + enddate + ']'
  else if startdate
    qrystr += 'CREATION_DATE:' + startdate
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '&resulttype=core&format=json'
  url += '&pageSize=' + size if size?
  url += '&page=' + (Math.floor(from/size)+1) if from?
  API.log 'Using eupmc for ' + url
  try
    res = HTTP.call 'GET',url
    return { total: res.data.hitCount, data: res.data.resultList.result}
  catch
    return { status: 'error', total: 0}

API.use.europepmc.licence = (pmcid,rec,fulltext,noui,cache,refresh=86400000) ->
  API.log msg: 'Europepmc licence checking', pmcid: pmcid, rec: rec?, fulltext: fulltext?, noui: noui

  if pmcid? or rec?.pmcid?
    if cache and cached = API.http.cache (pmcid ? rec.pmcid), 'epmc_licence'
      cached.cache = true
      return cached

  maybe_licence
  res = API.use.europepmc.search('PMC' + pmcid.toLowerCase().replace('pmc','')) if pmcid and not rec
  if res?.total > 0 or rec or fulltext
    rec ?= res.data[0]
    pmcid = rec.pmcid if not pmcid and rec
    
    if rec.license
      licinapi = {licence: rec.license,source:'epmc_api'}
      licinapi.licence = licinapi.licence.replace(/ /g,'-') if licinapi.licence.indexOf('cc') is 0
      API.http.cache pmcid, 'epmc_licence', licinapi
      return licinapi
      
    fulltext = API.use.europepmc.xml(pmcid) if not fulltext and pmcid
    if fulltext isnt 404 and typeof fulltext is 'string' and fulltext.indexOf('<') is 0
      licinperms = API.service.lantern.licence undefined,undefined,fulltext,'<permissions>','</permissions>'
      if licinperms.licence?
        licinperms.source = 'epmc_xml_permissions'
        API.http.cache pmcid, 'epmc_licence', licinperms
        return licinperms

      licanywhere = API.service.lantern.licence undefined,undefined,fulltext
      if licanywhere.licence?
        licanywhere.source = 'epmc_xml_outside_permissions'
        API.http.cache pmcid, 'epmc_licence', licanywhere
        return licanywhere

      if fulltext.indexOf('<permissions>') isnt -1
        maybe_licence = {licence:'non-standard-licence',source:'epmc_xml_permissions'}

    if pmcid and not noui and API.service?.lantern?.licence?
      url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
      pg = API.job.limit (API.settings.use?.europepmc?.limit ? 3000), 'API.http.puppeteer', [url,refresh], "EPMCUI"
      if typeof pg is 'string'
        licsplash = API.service.lantern.licence url, false, pg
        if licsplash.licence?
          licsplash.source = 'epmc_html'
          API.http.cache pmcid, 'epmc_licence', licsplash
          return licsplash

    API.http.cache(pmcid, 'epmc_licence', maybe_licence) if maybe_licence?
    return maybe_licence ? false
  else
    return false

API.use.europepmc.authorManuscript = (pmcid,rec,fulltext,noui,cache=true,refresh=86400000) ->
  if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
    return {aam:true,info:'fulltext'}
  else
    # if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    #rec = API.use.europepmc.search('PMC' + pmcid.toLowerCase().replace('pmc',''))?.data?[0] if pmcid and not rec
    pmcid ?= rec?.pmcid
    if pmcid
      if cache and cached = API.http.cache pmcid, 'epmc_aam'
        cached.cache = true
        return cached
      else
        fulltext = API.use.europepmc.xml pmcid
        if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
          resp = {aam:true,info:'fulltext'}
          API.http.cache pmcid, 'epmc_aam', resp
          return resp
        else if not noui
          url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
          #try
          pg = API.job.limit (API.settings.use?.europepmc?.limit ? 3000), 'API.http.puppeteer', [url,refresh], "EPMCUI"
          if pg is 404
            resp = {aam:false,info:'not in EPMC (404)'}
            API.http.cache pmcid, 'epmc_aam', resp
            return resp
          else if pg is 403
            API.log 'EPMC blocking us on author manuscript lookup', pmcid: pmcid
            return {info: 'EPMC blocking access, AAM status unknown'}
          else if typeof pg is 'string'
            s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal'
            s2 = 'Author manuscript; available in PMC'
            s3 = 'logo-nihpa.gif'
            s4 = 'logo-wtpa2.gif'
            if pg.indexOf(s1) isnt -1 or pg.indexOf(s2) isnt -1 or pg.indexOf(s3) isnt -1 or pg.indexOf(s4) isnt -1
              resp = {aam:true,info:'splashpage'}
              API.http.cache pmcid, 'epmc_aam', resp
              return resp
            else
              resp = {aam:false,info:'EPMC splashpage checked, no indicator found'}
              API.http.cache pmcid, 'epmc_aam', resp
              return resp
          else if pg?
            return {info: 'EPMC was accessed but aam could not be decided from what was returned'}
          else
            return {info: 'EPMC was accessed nothing was returned, so aam check could not be performed'}
          #catch err
          #  return {info:'Unknown error accessing EPMC', error: err.toString(), code: err.response?.statusCode}
  return {aam:false,info:''}

API.use.europepmc.xml = (pmcid) ->
  pmcid = pmcid.toLowerCase().replace('pmc','') if pmcid
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/PMC' + pmcid + '/fullTextXML'
  try
    r = HTTP.call 'GET', url
    if r.statusCode is 200
      return r.content
    else
      return false
  catch err
    return if err.response?.statusCode is 404 then err.response.statusCode else false

API.use.europepmc.xmlAvailable = (pmcid) ->
  pmcid = pmcid.toLowerCase().replace('pmc','') if pmcid
  cached = API.http.cache pmcid, 'epmc_xml'
  if cached
    return cached
  else
    available = API.use.europepmc.xml pmcid
    if available and typeof available is 'string' and available.indexOf('<') is 0
      API.http.cache pmcid, 'epmc_xml', true
      return true
    else
      API.http.cache(pmcid, 'epmc_xml', false) if available is 404
      return false

API.use.europepmc.format = (rec, metadata={}) ->
  try metadata.pdf ?= rec.pdf
  try metadata.open ?= rec.open
  try metadata.redirect ?= rec.redirect
  rec ?= if metadata.doi then API.use.europepmc.doi(metadata.doi) else if metadata.title then API.use.europepmc.title(metadata.title) else if metadata.pmid then API.use.europepmc.pmid(metadata.pmid) else API.use.europepmc.pmc metadata.pmcid
  try metadata.pmcid = rec.pmcid if rec.pmcid?
  try metadata.title = rec.title if rec.title?
  try metadata.doi = rec.doi if rec.doi?
  try metadata.pmid = rec.pmid if rec.pmid?
  try
    metadata.author = rec.authorList.author
    for a in metadata.author
      a.given = a.firstName
      a.family = a.lastName
      if a.affiliation?
        a.affiliation = a.affiliation[0] if _.isArray a.affiliation
        a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
  try metadata.journal ?= rec.journalInfo.journal.title
  try metadata.journal_short ?= rec.journalInfo.journal.isoAbbreviation
  try metadata.issue = rec.journalInfo.issue
  try metadata.volume = rec.journalInfo.volume
  try metadata.issn = rec.journalInfo.journal.issn
  try metadata.page = rec.pageInfo.toString()
  try metadata.keyword = rec.keywordList.keyword
  try
    for m in rec.meshHeadingList.meshHeading
      metadata.keyword ?= []
      metadata.keyword.push m.descriptorName if m.descriptorName and m.descriptorName not in metadata.keyword
  try
    for c in rec.chemicalList.chemical
      metadata.keyword ?= []
      metadata.keyword.push c.name if c.name and c.name not in metadata.keyword
  try metadata.year ?= rec.journalInfo.yearOfPublication
  try metadata.year ?= rec.journalInfo.printPublicationDate.split('-')[0]
  try 
    metadata.published ?= if rec.journalInfo.printPublicationDate.indexOf('-') isnt -1 then rec.journalInfo.printPublicationDate else if rec.electronicPublicationDate then rec.electronicPublicationDate else if rec.firstPublicationDate then rec.firstPublicationDate else undefined
    delete metadata.published if metadata.published.split('-').length isnt 3
  try metadata.abstract = API.convert.html2txt(rec.abstractText).replace(/\n/g,' ').replace('Abstract ','') if rec.abstractText?
  if rec?.license?
    metadata.licence = rec.license.trim().replace(/ /g,'-')
  if rec?.url?
    metadata.url = rec.url
    if not metadata.redirect? and typeof rec.url is 'string'
      try metadata.redirect = API.service.oab.redirect rec.url
  return metadata



API.use.europepmc.status = () ->
  try
    return true if HTTP.call 'GET', 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=*', {timeout: API.settings.use?.europepmc?.timeout ? API.settings.use?._timeout ? 4000}
  catch err
    return err.toString()

API.use.europepmc.test = (verbose) ->
  console.log('Starting europepmc test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.record = API.use.europepmc.pmc '3206455'
      delete result.record.url
      return false if not result.record.fullTextUrlList?
      delete result.record.fullTextUrlList
      return _.isEqual result.record, API.use.europepmc.test._examples.record
    () ->
      result.aam = API.use.europepmc.authorManuscript '3206455', undefined, undefined, undefined, false, 60000
      return result.aam.aam is false
    () ->
      result.licence = API.use.europepmc.licence '3206455', undefined, undefined, undefined, false, 60000
      return _.isEqual result.licence, API.use.europepmc.test._examples.licence
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending europepmc test') if API.settings.dev

  return result


API.use.europepmc.test._examples = {
  "licence": {
    "licence": "cc-by",
    "match": "This is an Open Access article distributed under the terms of the Creative Commons Attribution License",
    "matched": "thisisanopenaccessarticledistributedunderthetermsofthecreativecommonsattributionlicense",
    "source": "epmc_xml_permissions"
  },
  "record": {
    "id": "21999661",
    "source": "MED",
    "pmid": "21999661",
    "pmcid": "PMC3206455",
    "doi": "10.1186/1758-2946-3-47",
    "title": "Open bibliography for science, technology, and medicine.",
    "authorString": "Jones R, Macgillivray M, Murray-Rust P, Pitman J, Sefton P, O'Steen B, Waites W.",
    "authorList": {
      "author": [
        {
          "fullName": "Jones R",
          "firstName": "Richard",
          "lastName": "Jones",
          "initials": "R"
        },
        {
          "fullName": "Macgillivray M",
          "firstName": "Mark",
          "lastName": "Macgillivray",
          "initials": "M"
        },
        {
          "fullName": "Murray-Rust P",
          "firstName": "Peter",
          "lastName": "Murray-Rust",
          "initials": "P",
          "authorId": {
            "type": "ORCID",
            "value": "0000-0003-3386-3972"
          }
        },
        {
          "fullName": "Pitman J",
          "firstName": "Jim",
          "lastName": "Pitman",
          "initials": "J"
        },
        {
          "fullName": "Sefton P",
          "firstName": "Peter",
          "lastName": "Sefton",
          "initials": "P",
          "authorId": {
            "type": "ORCID",
            "value": "0000-0002-3545-944X"
          }
        },
        {
          "fullName": "O'Steen B",
          "firstName": "Ben",
          "lastName": "O'Steen",
          "initials": "B",
          "authorId": {
            "type": "ORCID",
            "value": "0000-0002-5175-7789"
          }
        },
        {
          "fullName": "Waites W",
          "firstName": "William",
          "lastName": "Waites",
          "initials": "W"
        }
      ]
    },
    "authorIdList": {
      "authorId": [
        {
          "type": "ORCID",
          "value": "0000-0003-3386-3972"
        },
        {
          "type": "ORCID",
          "value": "0000-0002-3545-944X"
        },
        {
          "type": "ORCID",
          "value": "0000-0002-5175-7789"
        }
      ]
    },
    "journalInfo": {
      "volume": "3",
      "journalIssueId": 1823303,
      "dateOfPublication": "2011 ",
      "monthOfPublication": 0,
      "yearOfPublication": 2011,
      "printPublicationDate": "2011-01-01",
      "journal": {
        "title": "Journal of Cheminformatics",
        "medlineAbbreviation": "J Cheminform",
        "isoabbreviation": "J Cheminform",
        "nlmid": "101516718",
        "essn": "1758-2946",
        "issn": "1758-2946"
      }
    },
    "pubYear": "2011",
    "pageInfo": "47",
    "abstractText": "The concept of Open Bibliography in science, technology and medicine (STM) is introduced as a combination of Open Source tools, Open specifications and Open bibliographic data. An Openly searchable and navigable network of bibliographic information and associated knowledge representations, a Bibliographic Knowledge Network, across all branches of Science, Technology and Medicine, has been designed and initiated. For this large scale endeavour, the engagement and cooperation of the multiple stakeholders in STM publishing - authors, librarians, publishers and administrators - is sought.",
    "affiliation": "Departments of Statistics and Mathematics, University of California, Berkeley, CA, USA. pitman@stat.berkeley.edu.",
    "language": "eng",
    "pubModel": "Electronic",
    "pubTypeList": {
      "pubType": [
        "research-article",
        "Journal Article"
      ]
    },
    "isOpenAccess": "Y",
    "inEPMC": "Y",
    "inPMC": "Y",
    "hasPDF": "Y",
    "hasBook": "N",
    "hasSuppl": "Y",
    "citedByCount": 3,
    "hasReferences": "N",
    "hasTextMinedTerms": "Y",
    "hasDbCrossReferences": "N",
    "hasLabsLinks": "Y",
    "license": "cc by",
    "authMan": "N",
    "epmcAuthMan": "N",
    "nihAuthMan": "N",
    "hasTMAccessionNumbers": "N",
    "dateOfCompletion": "2011-11-10",
    "dateOfCreation": "2011-11-02",
    "dateOfRevision": "2012-11-09",
    "electronicPublicationDate": "2011-10-14",
    "firstPublicationDate": "2011-10-14"
  }
}


