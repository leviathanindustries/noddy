
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
  baseurl = 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/'
  urlone = baseurl + 'epost.fcgi?db=pubmed&id=' + pmid
  try
    res = HTTP.call 'GET',urlone
    result = API.convert.xml2json undefined,res.content
    querykey = result.ePostResult.QueryKey[0]
    webenv = result.ePostResult.WebEnv[0]
    urltwo = baseurl + 'esummary.fcgi?db=pubmed&query_key=' + querykey + '&WebEnv=' + webenv
    restwo = HTTP.call 'GET',urltwo
    md = API.convert.xml2json undefined,restwo.content
    rec = md.eSummaryResult.DocSum[0]
    frec = {id:rec.Id[0]}
    for ii in rec.Item
      if ii.$.Type is 'List'
        frec[ii.$.Name] = []
        for si in ii.Item
          sio = {}
          sio[si.$.Name] = si._
          frec[ii.$.Name].push sio
      else
        frec[ii.$.Name] = ii._
    return {data:frec}
  catch err
    return {status:'error', error: err}

API.use.pubmed.aheadofprint = (pmid) ->
  pubmed_xml_url = 'http://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
  res = HTTP.call 'GET', pubmed_xml_url
  return res.content?.indexOf('PublicationStatus&gt;aheadofprint&lt;/PublicationStatus') isnt -1




