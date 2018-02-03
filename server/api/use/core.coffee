

# core docs:
# http://core.ac.uk/docs/
# http://core.ac.uk/docs/#!/articles/searchArticles
# http://core.ac.uk:80/api-v2/articles/search/doi:"10.1186/1471-2458-6-309"

API.use ?= {}
API.use.core = {}

API.add 'use/core/doi/:doipre/:doipost',
  get: () -> return API.use.core.doi this.urlParams.doipre + '/' + this.urlParams.doipost


API.add 'use/core/search/:qry',
  get: () -> return API.use.core.search this.urlParams.qry, this.queryParams.from, this.queryParams.size

API.use.core.doi = (doi) ->
  return API.use.core.get 'doi:"' + doi + '"'

API.use.core.title = (title) ->
  return API.use.core.get 'title:"' + doi + '"'

API.use.core.get = (qrystr) ->
  res = API.http.cache qrystr, 'core_get'
  if not res?
    ret = API.use.core.search qrystr
    if ret.total
      res = ret.data[0]
      for i in ret.data
        if i.hasFullText is "true"
          res = i
          break
  if res?
    op = API.use.core.redirect res
    res.url = op.url
    res.redirect = op.redirect
    API.http.cache qrystr, 'core_get', res
  return res

API.use.core.search = (qrystr,from,size=10,timeout=10000) ->
  # assume incoming query string is of ES query string format
  # assume from and size are ES typical
  # but core only accepts certain field searches:
  # title, description, fullText, authorsString, publisher, repositoryIds, doi, identifiers, language.name and year
  # for paging core uses "page" from 1 (but can only go up to 100?) and "pageSize" defaulting to 10 but can go up to 100
  apikey = API.settings.use.core.apikey
  return { status: 'error', data: 'NO CORE API KEY PRESENT!'} if not apikey
  #var qry = '"' + qrystr.replace(/\w+?\:/g,'') + '"'; # TODO have this accept the above list
  url = 'http://core.ac.uk/api-v2/articles/search/' + qrystr + '?urls=true&apiKey=' + apikey
  url += '&pageSize=' + size if size isnt 10
  url += '&page=' + (Math.floor(from/size)+1) if from
  API.log 'Using CORE for ' + url
  try
    res = HTTP.call 'GET', url, {timeout:timeout}
    return if res.statusCode is 200 then { total: res.data.totalHits, data: res.data.data} else { status: 'error', data: res}
  catch err
    return {status: 'error', error: err.toString()}

API.use.core.redirect = (record) ->
  res = {}
  if record.fulltextIdentifier
    res.url = record.fulltextIdentifier
    res.redirect = API.service.oab.redirect(record.fulltextIdentifier) if API.service.oab?
  if res.redirect is false
    for u in record.fulltextUrls
      if u.indexOf('core.ac.uk') isnt -1
        res.url = u # no need to redirect, links in core are open
        break
      else
        resolved = API.http.resolve u
        if resolved and resolved.indexOf('.pdf') isnt -1
          # no good way to know if a resolved URL can actually be accessed, so only use it if it seems to be a pdf (which is usually accessible)
          res.url = resolved
          res.redirect = API.service.oab.redirect(res.url) if res.url? and API.service.oab?
          break if res.redirect isnt false
  return res



API.use.core.status = () ->
  return API.use.core.search('doi:"10.1186/1758-2946-3-47"', undefined, undefined, 3000).status isnt 'error'

API.use.core.test = (verbose) ->
  result = {passed:[],failed:[]}
  tests = [
    () ->
      ret = API.use.core.search 'doi:"10.1186/1758-2946-3-47"'
      if ret.total
        res = ret.data[0]
        for i in ret.data
          if i.hasFullText is "true"
            result.record = i
            break
      return _.isEqual result.record, API.use.core.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result

API.use.core.test._examples = {
  record: {
    "id": "81869340",
    "authors": [
      "Richard Jones",
      "Mark MacGillivray",
      "Peter Murray-Rust",
      "Jim Pitman",
      "Peter Sefton",
      "Ben O'Steen",
      "William Waites"
    ],
    "contributors": [],
    "datePublished": "2011",
    "identifiers": [
      "10.1186/1758-2946-3-47"
    ],
    "publisher": "Springer Nature",
    "relations": [
      "http://dx.doi.org/10.1186/1758-2946-3-47"
    ],
    "repositories": [
      {
        "id": "2612",
        "openDoarId": 0,
        "name": "Springer - Publisher Connector",
        "uri": null,
        "uriJournals": null,
        "physicalName": "noname",
        "source": null,
        "software": null,
        "metadataFormat": null,
        "description": null,
        "journal": null,
        "pdfStatus": null,
        "nrUpdates": 0,
        "disabled": false,
        "lastUpdateTime": null,
        "metadataRecordCount": 0,
        "metadataDeletedRecordCount": 0,
        "metadataLinkCount": 0,
        "metadataSize": 0,
        "journalMetadataSize": 0,
        "metadataAge": null,
        "journalMetadataAge": null,
        "metadataInIndexCount": 0,
        "metadataDeletedInIndexCount": 0,
        "metadataAlloweInIndexCount": 0,
        "metadataDisabledInIndexCount": 0,
        "metadataExtractionDate": null,
        "journalMetadataExtractionDate": null,
        "databaseRecordCount": 0,
        "databaseDeletedRecordCount": 0,
        "databasePdfLinkCount": 0,
        "databasePdfCount": 0,
        "databaseDeletedPdfCount": 0,
        "hardDrivePdfSize": 0,
        "hardDrivePdfCount": 0,
        "hardDriveDeletedPdfCount": 0,
        "databaseTextCount": 0,
        "databaseTextNotDeletedCount": 0,
        "hardDriveTextCount": 0,
        "hardDriveDeletedTextCount": 0,
        "databaseIndexCount": 0,
        "indexRecordCount": 0,
        "indexJournalCount": 0,
        "indexTextCount": 0,
        "metadataOnlyIndex": 0,
        "indexTextCountDB": 0,
        "indexedPdfDB": 0,
        "indexedDisabledDB": 0,
        "indexTextNotDeletedCount": 0,
        "hardDriveCitationFiles": 0,
        "citationFilesDb": 0,
        "crawlingLimit": 0,
        "citationCount": 0,
        "citationWithDocCount": 0,
        "citationDoiCount": 0,
        "documentDoiCount": 0,
        "documentDoiWithFulltextCount": 0,
        "repositoryLocation": null
      }
    ],
    "subjects": [
      "journal-article"
    ],
    "title": "Open Bibliography for Science, Technology, and Medicine",
    "topics": [],
    "types": [],
    "year": 2011,
    "fulltextUrls": [
      "https://core.ac.uk/download/pdf/81869340.pdf",
      "https://core.ac.uk/display/81869340"
    ],
    "fulltextIdentifier": "https://core.ac.uk/download/pdf/81869340.pdf",
    "doi": "10.1186/1758-2946-3-47",
    "downloadUrl": "https://core.ac.uk/download/pdf/81869340.pdf",
    "url": "https://core.ac.uk/download/pdf/81869340.pdf",
    "redirect": "https://core.ac.uk/download/pdf/81869340.pdf"
  }
}