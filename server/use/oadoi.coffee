

API.use ?= {}
API.use.oadoi = {}

API.add 'use/oadoi/:doipre/:doipost',
  get: () -> return API.use.oadoi.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.use.oadoi.doi = (doi) ->
  url = 'https://api.oadoi.org/v2/' + doi + '?email=mark@cottagelabs.com'
  API.log 'Using oadoi for ' + url
  res = API.http.cache doi, 'oadoi_doi'
  if not res?
    try
      res = HTTP.call 'GET', url
      if res.statusCode is 200
        res = res.data
        #res.url = API.http.resolve(res.best_oa_location.url) if res?.best_oa_location?.url?
        # for now we trust oadoi URLs instead of resolving them, to speed things up
        res.url = res?.best_oa_location?.url
        API.http.cache doi, 'oadoi_doi', res
      else
        return undefined
    catch
      return undefined
  res.redirect = API.service.oab.redirect(res.url) if res?.url? and API.service.oab?
  return res



API.use.oadoi.status = () ->
  try
    return true if HTTP.call 'GET', 'http://api.oadoi.org/v2/', {timeout: API.settings.use?.oadoi?.timeout ? API.settings.use?._timeout ? 4000}
  catch err
    return err.toString()

API.use.oadoi.test = (verbose) ->
  console.log('Starting oadoi test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call 'GET', 'http://api.oadoi.org/v2/10.1186/1758-2946-3-47?email=mark+status@cottagelabs.com'
      result.record = result.record.data if result.record?.data?
      return false if not result.record.oa_locations?
      delete result.record.oa_locations
      delete result.record.updated
      return _.isEqual result.record, API.use.oadoi.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending oadoi test') if API.settings.dev

  return result



API.use.oadoi.test._examples = {
  record: {
    "best_oa_location": {
      "evidence": "open (via page says license)",
      "host_type": "publisher",
      "is_best": true,
      "license": "cc-by",
      "pmh_id": null,
      "updated": "2017-09-13T16:15:37.200715",
      "url": "https://jcheminf.springeropen.com/track/pdf/10.1186/1758-2946-3-47?site=jcheminf.springeropen.com",
      "url_for_landing_page": "http://doi.org/10.1186/1758-2946-3-47",
      "url_for_pdf": "https://jcheminf.springeropen.com/track/pdf/10.1186/1758-2946-3-47?site=jcheminf.springeropen.com",
      "version": "publishedVersion"
    },
    "data_standard": 2,
    "doi": "10.1186/1758-2946-3-47",
    "doi_url": "https://doi.org/10.1186/1758-2946-3-47",
    "genre": "journal-article",
    "is_oa": true,
    "journal_is_in_doaj": true,
    "journal_is_oa": true,
    "journal_issns": "1758-2946",
    "journal_name": "Journal of Cheminformatics",
    "published_date": "2011-01-01",
    "publisher": "Springer Nature",
    "title": "Open Bibliography for Science, Technology, and Medicine",
    "x_reported_noncompliant_copies": [],
    "year": 2011,
    "z_authors": [
      {
        "family": "Jones",
        "given": "Richard"
      },
      {
        "family": "MacGillivray",
        "given": "Mark"
      },
      {
        "family": "Murray-Rust",
        "given": "Peter"
      },
      {
        "family": "Pitman",
        "given": "Jim"
      },
      {
        "family": "Sefton",
        "given": "Peter"
      },
      {
        "family": "O'Steen",
        "given": "Ben"
      },
      {
        "family": "Waites",
        "given": "William"
      }
    ]
  }
}