

# pubmed API http://www.ncbi.nlm.nih.gov/books/NBK25497/
# examples http://www.ncbi.nlm.nih.gov/books/NBK25498/#chapter3.ESearch__ESummaryEFetch
# get a pmid - need first to issue a query to get some IDs...
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?id=21999661&db=pubmed
# then scrape the QueryKey and WebEnv values from it and use like so:
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&query_key=1&WebEnv=NCID_1_54953983_165.112.9.28_9001_1461227951_1012752855_0MetA0_S_MegaStore_F_1

API.use ?= {}
API.use.pubmed = {}

API.add 'use/pubmed/:pmid', get: () -> return API.use.pubmed.pmid this.urlParams.pmid


API.use.pubmed.pmid = (pmid) ->
  baseurl = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/'
  urlone = baseurl + 'epost.fcgi?db=pubmed&id=' + pmid
  API.log 'Using pubmed step 1 for ' + urlone
  try
    res = HTTP.call 'GET',urlone
    result = API.convert.xml2json res.content
    querykey = result.ePostResult.QueryKey[0]
    webenv = result.ePostResult.WebEnv[0]
    urltwo = baseurl + 'esummary.fcgi?db=pubmed&query_key=' + querykey + '&WebEnv=' + webenv
    API.log 'Using pubmed step 2 for ' + urltwo
    restwo = HTTP.call 'GET',urltwo
    md = API.convert.xml2json restwo.content
    rec = md.eSummaryResult.DocSum[0]
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
    return frec
  catch err
    return {status:'error', error: err.toString()}

API.use.pubmed.aheadofprint = (pmid) ->
  pubmed_xml_url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
  try
    res = HTTP.call 'GET', pubmed_xml_url
    return res.content?.indexOf('PublicationStatus&gt;aheadofprint&lt;/PublicationStatus') isnt -1
  catch
    return false


API.use.pubmed.status = () ->
  try
    return HTTP.call('GET', 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi', {timeout: API.settings.use?.europepmc?.timeout ? API.settings.use?._timeout ? 4000}).statusCode is 200
  catch err
    return err.toString()


API.use.pubmed.test = (verbose) ->
  console.log('Starting pubmed test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.record = API.use.pubmed.pmid '23908565'
      delete result.record.EPubDate # don't know what happens to these, so just remove them...
      delete result.record.ELocationID
      return _.isEqual result.record, API.use.pubmed.test._examples.record
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