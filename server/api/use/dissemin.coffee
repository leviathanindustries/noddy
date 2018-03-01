

# at 17/01/2016 dissemin searches crossref, base, sherpa/romeo, zotero primarily,
# and arxiv, hal, pmc, openaire, doaj, perse, cairn.info, numdam secondarily via oa-pmh
# see http://dissem.in/sources
# http://dev.dissem.in/api.html

API.use ?= {}
API.use.dissemin = {}

API.add 'use/dissemin/doi/:doipre/:doipost',
  get: () -> return API.use.dissemin.doi this.urlParams.doipre + '/' + this.urlParams.doipost


API.use.dissemin.doi = (doi) ->
  url = 'http://beta.dissem.in/api/' + doi
  API.log 'Using dissemin for ' + url
  res = API.http.cache doi, 'dissemin_doi'
  if not res?
    try
      res = HTTP.call('GET', url).data.paper
      res.url = API.http.resolve res.pdf_url
      API.http.cache doi, 'dissemin_doi', res
  try res.redirect = API.service.oab.redirect res.url
  return res



API.use.dissemin.status = () ->
  try
    h = HTTP.call('GET', 'http://beta.dissem.in/api/10.1186/1758-2946-3-47',{timeout: API.settings.use?.dissemin?.timeout ? API.settings.use?._timeout ? 2000})
    return if h.data.paper then true else h.data
  catch err
    return err.toString()

API.use.dissemin.test = (verbose) ->
  console.log('Starting dissemin test') if API.settings.dev

  result = {passed:[],failed:[]}
  tests = [
    () ->
      result.record = HTTP.call('GET', 'http://beta.dissem.in/api/10.1186/1758-2946-3-47')
      result.record = result.record.data.paper if result.record?.data?.paper?
      return false if not result.record.records? or result.record.records.length is 0 # this list can reasonably change length
      delete result.record.records
      return _.isEqual result.record, API.use.dissemin.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending dissemin test') if API.settings.dev

  return result



API.use.dissemin.test._examples = {
  record:{
    "classification": "OA",
    "title": "Open Bibliography for Science, Technology, and Medicine",
    "pdf_url": "http://dx.doi.org/10.1186/1758-2946-3-47",
    "authors": [
      {
        "name": {
          "last": "Jones",
          "first": "Richard"
        }
      },
      {
        "name": {
          "last": "MacGillivray",
          "first": "Mark"
        }
      },
      {
        "orcid": "0000-0003-3386-3972",
        "name": {
          "last": "Murray-Rust",
          "first": "Peter"
        }
      },
      {
        "name": {
          "last": "Pitman",
          "first": "Jim"
        }
      },
      {
        "name": {
          "last": "Sefton",
          "first": "Peter"
        }
      },
      {
        "name": {
          "last": "O'Steen",
          "first": "Ben"
        }
      },
      {
        "name": {
          "last": "Waites",
          "first": "William"
        }
      }
    ],
    "date": "2011-01-01",
    "type": "journal-article"
  }
}

