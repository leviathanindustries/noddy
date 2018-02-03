

# https://developers.exlibrisgroup.com/primo/apis/webservices/gettingstarted
# https://developers.exlibrisgroup.com/primo/apis/webservices/soap/search
# https://developers.exlibrisgroup.com/primo/apis/webservices/xservices/search/briefsearch
# appears to requires identification as a given institution, e.g. as Imperial do:
# Imperial searches require the parameter 'institution=44IMP'.
# http://imp-primo.hosted.exlibrisgroup.com/PrimoWebServices/xservice/search/brief?institution=44IMP&indx=1&bulkSize=10&query=any,contains,science
# http://imp-primo.hosted.exlibrisgroup.com/PrimoWebServices/xservice/search/brief?institution=44IMP&onCampus=true&query=any,exact,lok&indx=1&bulkSize=2&dym=true&highlight=true&lang=eng
# http://imp-primo.hosted.exlibrisgroup.com:80/PrimoWebServices/xservice/search/brief?query=any,contains,cheese&institution=44IMP&onCampus=true&dym=false&indx=1&bulkSize=20&loc=adaptor,primo_central_multiple_fe

# Imperial also said: It appears that usually XServices uses port 1701 for Primo Central results and 80 for Metalib. But for whatever reason ours just uses 80 for
# all of them. You can restrict the search to only Primo Central results by adding the parameter 'loc=adaptor,primo_central_multiple_fe'.

API.use.exlibris = {}

API.add 'use/exlibris/primo',
  get: () ->
    return API.use.exlibris.primo this.queryParams.q, this.queryParams.from, this.queryParams.size, this.queryParams.institution, this.queryParams.url, this.queryParams.raw



API.use.exlibris.parse = (rec) ->
  #  NOTE there is quite a lot more in here that could be useful...
  res = {}
  res.library ?= rec.LIBRARIES?.LIBRARY
  if rec.PrimoNMBib?.record?.display
    res.title = rec.PrimoNMBib.record.display.title
    res.type = rec.PrimoNMBib.record.display.type
    res.publisher = rec.PrimoNMBib.record.display.publisher
    res.contributor = rec.PrimoNMBib.record.display.contributor
    res.creator = rec.PrimoNMBib.record.display.creator
  if rec.PrimoNMBib?.record?.search
    res.subject = rec.PrimoNMBib.record.search.subject
  if rec.PrimoNMBib?.record?.links?.linktorsrc
    res.repository = rec.PrimoNMBib.record.links.linktorsrc.replace('$$U','')
  return res

API.use.exlibris.primo = (qry, from=0, size=10, institution='44IMP', tgt='http://imp-primo.hosted.exlibrisgroup.com', raw) ->
  index = from + 1
  institution = '44IMP' if institution.toLowerCase() is 'imperial'
  if institution.toLowerCase() in ['york','44york']
    institution = '44YORK'
    tgt = 'https://yorsearch.york.ac.uk'
  # TODO add mappings of institutions we want to search on
  query
  if qry.indexOf(',contains,') isnt -1 or qry.indexOf(',exact,') isnt -1 or qry.indexOf(',begins_with,') isnt -1 or qry.indexOf('&') isnt -1
    query = qry
  else if qry.indexOf(':') isnt -1
    qry = qry.split(':')[1]
    within = qry.split(':')[0]
    query = within + ',exact,' + qry
  else
    query = 'any,contains,' + qry
  url = tgt + '/PrimoWebServices/xservice/search/brief?json=true&institution=' + institution + '&indx=' + index + '&bulkSize=' + size + '&query=' + query
  API.log 'Using exlibris for ' + url
  try
    res = HTTP.call 'GET', url
    data
    if res.statusCode is 200
      if raw
        try
          data = res.data.SEGMENTS.JAGROOT.RESULT.DOCSET.DOC
        catch
          data = res.data.SEGMENTS.JAGROOT.RESULT
      else
        data = []
        try
          res.data.SEGMENTS.JAGROOT.RESULT.DOCSET.DOC = [res.data.SEGMENTS.JAGROOT.RESULT.DOCSET.DOC]if not res.data.SEGMENTS.JAGROOT.RESULT.DOCSET.DOC instanceof Array
          data.push(API.use.exlibris.parse(r)) for r in res.data.SEGMENTS.JAGROOT.RESULT.DOCSET.DOC
      fcts = []
      try fcts = res.data.SEGMENTS.JAGROOT.RESULT.FACETLIST.FACET
      facets = {}
      for f in fcts
        facets[f['@NAME']] = {}
        for fc in f.FACET_VALUES
          facets[f['@NAME']][f.FACET_VALUES[fc]['@KEY']] = f.FACET_VALUES[fc]['@VALUE']
      total = 0
      try total = res.data.SEGMENTS.JAGROOT.RESULT.DOCSET['@TOTALHITS']
      return { query: query, total: total, data: data, facets: facets}
    else
      return { status: 'error', data: res}
  catch err
    return status: 'error', error: err.toString()

