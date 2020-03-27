
_decodeEntities = (str) ->
  re = /&(nbsp|amp|quot|lt|gt);/g
  translate = "nbsp" : " ", "amp" : "&", "quot" : "\"", "lt" : "<", "gt" : ">"
  return str.replace(re, (match, entity) ->
    return translate[entity];
  ).replace(/&#(\d+);/gi, (match, numStr) ->
    return String.fromCharCode parseInt numStr, 10
  )

# pubmed API http://www.ncbi.nlm.nih.gov/books/NBK25497/
# examples http://www.ncbi.nlm.nih.gov/books/NBK25498/#chapter3.ESearch__ESummaryEFetch
# get a pmid - need first to issue a query to get some IDs...
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?id=21999661&db=pubmed
# then scrape the QueryKey and WebEnv values from it and use like so:
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&query_key=1&WebEnv=NCID_1_54953983_165.112.9.28_9001_1461227951_1012752855_0MetA0_S_MegaStore_F_1

API.use ?= {}
API.use.pubmed = {}

API.add 'use/pubmed/search/:q', get: () -> return API.use.pubmed.search this.urlParams.q, this.queryParams.full?, this.queryParams.size, this.queryParams.ids?
API.add 'use/pubmed/:pmid', get: () -> return API.use.pubmed.pmid this.urlParams.pmid
API.add 'use/pubmed/summary/:pmid', 
  get: () -> 
    res = API.use.pubmed.entrez.summary undefined, undefined, this.urlParams.pmid
    return if this.queryParams.format then API.use.pubmed.format(res) else res



API.use.pubmed.entrez = {}
API.use.pubmed.entrez.summary = (qk,webenv,id) ->
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed'
  if id?
    id = id.join(',') if _.isArray id
    url += '&id=' + id # can be a comma separated list as well
  else
    url += '&query_key=' + qk + '&WebEnv=' + webenv
  API.log 'Using pubmed entrez summary for ' + url
  try
    res = HTTP.call 'GET', url
    md = API.convert.xml2json res.content, undefined, false
    recs = []
    for rec in md.eSummaryResult.DocSum
      frec = {id:rec.Id[0]}
      for ii in rec.Item
        if ii.$.Type is 'List'
          frec[ii.$.Name] = []
          if ii.Item?
            for si in ii.Item
              sio = {}
              sio[si.$.Name] = si._
              frec[ii.$.Name].push sio
        else
          frec[ii.$.Name] = ii._
      recs.push frec
      if not id? or id.indexOf(',') is -1
        return recs[0]
        break
    return recs
  catch
    return undefined

API.use.pubmed.entrez.pmid = (pmid) ->
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?db=pubmed&id=' + pmid
  API.log 'Using pubmed entrez post for ' + url
  try
    res = HTTP.call 'GET', url
    result = API.convert.xml2json res.content, undefined, false
    return API.use.pubmed.entrez.summary result.ePostResult.QueryKey[0], result.ePostResult.WebEnv[0]
  catch
    return undefined

API.use.pubmed.search = (str,full,size=10,ids=false) ->
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmax=' + size + '&sort=pub date&term=' + str
  API.log 'Using pubmed entrez search for ' + url
  try
    ids = ids.split(',') if typeof ids is 'string'
    if _.isArray ids
      res = {total: ids.length, data: []}
    else
      res = HTTP.call 'GET', url
      result = API.convert.xml2json res.content, undefined, false
      res = {total: result.eSearchResult.Count[0], data: []}
      if ids is true
        res.data = result.eSearchResult.IdList[0].Id
        return res
      else
        ids = result.eSearchResult.IdList[0].Id
    if full # may need a rate limiter on this
      for uid in ids
        pg = API.job.limit 300, 'API.use.pubmed.pmid', [uid], "PUBMED_SEARCH_PMID"
        res.data.push pg
        break if res.data.length is size
    else
      urlids = []
      for id in ids
        break if res.data.length is size
        urlids.push id
        if urlids.length is 40
          for rec in API.use.pubmed.entrez.summary undefined, undefined, urlids
            res.data.push API.use.pubmed.format rec
            break if res.data.length is size
          urlids = []
      if urlids.length
        for rec in API.use.pubmed.entrez.summary undefined, undefined, urlids
          res.data.push API.use.pubmed.format rec
          break if res.data.length is size
    return res
  catch err
    return {status:'error', error: err.toString()}

API.use.pubmed.pmid = (pmid) ->
  try
    url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
    res = HTTP.call 'GET', url
    if res?.content? and res.content.indexOf('<') is 0
      return API.use.pubmed.format _decodeEntities res.content.split('<pre>')[1].split('</pre>')[0].replace('\n','')
  try
    return API.use.pubmed.format API.use.pubmed.entrez.pmid pmid
  return undefined

API.use.pubmed.aheadofprint = (pmid) ->
  try
    res = HTTP.call 'GET', 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
    return res.content?.indexOf('PublicationStatus&gt;aheadofprint&lt;/PublicationStatus') isnt -1
  catch
    return false

API.use.pubmed.format = (rec, metadata={}) ->
  if typeof rec is 'string' and rec.indexOf('<') is 0
    rec = API.convert.xml2json rec, undefined, false
  if rec.eSummaryResult?.DocSum? or rec.ArticleIds
    frec = {}
    if rec.eSummaryResult?.DocSum?
      rec = md.eSummaryResult.DocSum[0]
      for ii in rec.Item
        if ii.$.Type is 'List'
          frec[ii.$.Name] = []
          if ii.Item?
            for si in ii.Item
              sio = {}
              sio[si.$.Name] = si._
              frec[ii.$.Name].push sio
        else
          frec[ii.$.Name] = ii._
    else
      frec = rec
    try metadata.pmid ?= rec.Id[0]
    try metadata.pmid ?= rec.id
    try metadata.title ?= frec.Title
    try metadata.issn ?= frec.ISSN
    try metadata.essn ?= frec.ESSN
    try metadata.doi ?= frec.DOI
    try metadata.journal ?= frec.FullJournalName
    try metadata.journal_short ?= frec.Source
    try metadata.volume ?= frec.Volume
    try metadata.issue ?= frec.Issue
    try metadata.page ?= frec.Pages #like 13-29 how to handle this
    try metadata.year ?= frec[if frec.PubDate then 'PubDate' else 'EPubDate'].split(' ')[0]
    try
      p = frec[if frec.PubDate then 'PubDate' else 'EPubDate'].split ' '
      metadata.published ?= p[0] + '-' + (['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(p[1].toLowerCase()) + 1) + '-' + (if p.length is 3 then p[2] else '01')
    if frec.AuthorList?
      metadata.author ?= []
      for a in frec.AuthorList
        try
          a.family = a.Author.split(' ')[0]
          a.given = a.Author.replace(a.family + ' ','')
          a.name = a.given + ' ' + a.family
          metadata.author.push a
    if frec.ArticleIds? and not metadata.pmcid?
      for ai in frec.ArticleIds
        if ai.pmc # pmcid or pmc? replace PMC in the value? it will be present
          metadata.pmcid ?= ai.pmc
          break
  else if rec.PubmedArticle?
    rec = rec.PubmedArticle
    mc = rec.MedlineCitation[0]
    try metadata.pmid ?= mc.PMID[0]._
    try metadata.title ?= mc.Article[0].ArticleTitle[0]
    try metadata.issn ?= mc.Article[0].Journal[0].ISSN[0]._
    try metadata.journal ?= mc.Article[0].Journal[0].Title[0]
    try metadata.journal_short ?= mc.Article[0].Journal[0].ISOAbbreviation[0]
    try
      pd = mc.Article[0].Journal[0].JournalIssue[0].PubDate[0]
      try metadata.year ?= pd.Year[0]
      try metadata.published ?= pd.Year[0] + '-' + (if pd.Month then (['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(pd.Month[0].toLowerCase()) + 1) else '01') + '-' + (if pd.Day then pd.Day[0] else '01')
    try
      metadata.author ?= []
      for ar in mc.Article[0].AuthorList[0].Author
        a = {}
        a.family = ar.LastName[0]
        a.given = ar.ForeName[0]
        a.name = if a.Author then a.Author else a.given + ' ' + a.family
        try a.affiliation = ar.AffiliationInfo[0].Affiliation[0]
        if a.affiliation?
          a.affiliation = a.affiliation[0] if _.isArray a.affiliation
          a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
        metadata.author.push a
    try
      for pid in rec.PubmedData[0].ArticleIdList[0].ArticleId
        if pid.$.IdType is 'doi'
          metadata.doi ?= pid._
          break
    try
      metadata.reference ?= []
      for ref in rec.PubmedData[0].ReferenceList[0].Reference
        rc = ref.Citation[0]
        rf = {}
        rf.doi = rc.split('doi.org/')[1].trim() if rc.indexOf('doi.org/') isnt -1
        try
          rf.author = []
          rf.author.push({name: an}) for an in rc.split('. ')[0].split(', ')
        try rf.title = rc.split('. ')[1].split('?')[0].trim()
        try rf.journal = rc.replace(/\?/g,'.').split('. ')[2].trim()
        try
          rf.url = 'http' + rc.split('http')[1].split(' ')[0]
          delete rf.url if rf.url.indexOf('doi.org') isnt -1 
        metadata.reference.push(rf) if not _.isEmpty rf
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  try metadata.open ?= rec.open
  try metadata.redirect ?= rec.redirect
  return metadata



API.use.pubmed.status = () ->
  try
    return HTTP.call('GET', 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi', {timeout: API.settings.use?.europepmc?.timeout ? API.settings.use?._timeout ? 4000}).statusCode is 200
  catch err
    return err.toString()

API.use.pubmed.test = (verbose) ->
  console.log('Starting pubmed test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    #() -> the below example is no longer accurate to the output of the function
    #  result.record = API.use.pubmed.pmid '23908565'
    #  delete result.record.EPubDate # don't know what happens to these, so just remove them...
    #  delete result.record.ELocationID
    #  return _.isEqual result.record, API.use.pubmed.test._examples.record
    () ->
      result.aheadofprint = API.use.pubmed.aheadofprint '23908565'
      return result.aheadofprint is false # TODO add one that is true
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending pubmed test') if API.settings.dev

  return result

API.use.pubmed.test._examples = {
  record: {
    "id": "23908565",
    "PubDate": "2012 Dec",
    "Source": "Hist Human Sci",
    "AuthorList": [
      {
        "Author": "Jackson M"
      }
    ],
    "LastAuthor": "Jackson M",
    "Title": "The pursuit of happiness: The social and scientific origins of Hans Selye's natural philosophy of life.",
    "Volume": "25",
    "Issue": "5",
    "Pages": "13-29",
    "LangList": [
      {
        "Lang": "English"
      }
    ],
    "NlmUniqueID": "100967737",
    "ISSN": "0952-6951",
    "ESSN": "1461-720X",
    "PubTypeList": [
      {
        "PubType": "Journal Article"
      }
    ],
    "RecordStatus": "PubMed",
    "PubStatus": "ppublish",
    "ArticleIds": [
      {
        "pubmed": "23908565"
      },
      {
        "doi": "10.1177/0952695112468526"
      },
      {
        "pii": "10.1177_0952695112468526"
      },
      {
        "pmc": "PMC3724273"
      },
      {
        "rid": "23908565"
      },
      {
        "eid": "23908565"
      },
      {
        "pmcid": "pmc-id: PMC3724273;"
      }
    ],
    "DOI": "10.1177/0952695112468526",
    "History": [
      {
        "entrez": "2013/08/03 06:00"
      },
      {
        "pubmed": "2013/08/03 06:00"
      },
      {
        "medline": "2013/08/03 06:00"
      }
    ],
    "References": [],
    "HasAbstract": "1",
    "PmcRefCount": "0",
    "FullJournalName": "History of the human sciences",
    "SO": "2012 Dec;25(5):13-29"
  }
}