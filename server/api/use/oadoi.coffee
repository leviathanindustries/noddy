

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
        res.url = API.http.resolve(res.best_oa_location.url) if res?.best_oa_location?.url?
        API.http.cache doi, 'oadoi_doi', res
      else
        return undefined
    catch
      return undefined
  res.redirect = API.service.oab.redirect(res.url) if res?.url? and API.service.oab?
  return res



API.use.oadoi.status = () ->
  try
    return true if HTTP.call 'GET', 'http://api.oadoi.org/v2/', {timeout:2000}
  catch
    return false

API.use.oadoi.test = (verbose) ->
  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call('GET', 'http://api.oadoi.org/v2/10.1186/1758-2946-3-47?email=mark+status@cottagelabs.com').data
      return _.isEqual result.record, API.use.oadoi.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
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
    "oa_locations": [
      {
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
      {
        "evidence": "oa journal (via issn in doaj)",
        "host_type": "publisher",
        "is_best": false,
        "license": "cc-by",
        "pmh_id": null,
        "updated": "2017-12-01T00:25:35.979832",
        "url": "https://doi.org/10.1186/1758-2946-3-47",
        "url_for_landing_page": "https://doi.org/10.1186/1758-2946-3-47",
        "url_for_pdf": null,
        "version": "publishedVersion"
      },
      {
        "evidence": "oa repository (via pmcid lookup)",
        "host_type": "repository",
        "is_best": false,
        "license": null,
        "pmh_id": null,
        "updated": "2017-12-01T00:25:35.979966",
        "url": "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3206455/pdf",
        "url_for_landing_page": "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3206455",
        "url_for_pdf": "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3206455/pdf",
        "version": "publishedVersion"
      }
    ],
    "publisher": "Springer Nature",
    "title": "Open Bibliography for Science, Technology, and Medicine",
    "updated": "2017-11-14T19:36:31.059973",
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