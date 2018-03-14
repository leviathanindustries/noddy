

# Docs: https://europepmc.org/GristAPI
# Fields you can search by: https://europepmc.org/GristAPI#API

# Example, get info by grant ID: http://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=gid:088130&resultType=core&format=json
# Use case: To get the name of a Principal Investigator, call API.use.grist.grant_id(the_grant_id).data.Person
# Will return {FamilyName: "Friston", GivenName: "Karl", Initials: "KJ", Title: "Prof"}

API.use ?= {}
API.use.grist = {}

API.add 'use/grist/grant_id/:qry',
  get: () -> return API.use.grist.grant_id this.urlParams.qry

API.use.grist.grant_id = (grant_id) ->
  return API.use.grist.search 'gid:' + grant_id

API.use.grist.search = (qrystr,from,page) ->
  GRIST_API_PAGE_SIZE = 25;  # it's hardcoded to 25 according to the docs
  # note in Grist API one of the params is resultType, in EPMC REST API the same param is resulttype .
  url = 'https://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=' + qrystr + '&resultType=core&format=json'
  url += '&page=' + (Math.floor(from/GRIST_API_PAGE_SIZE)+1) if from?
  API.log 'Using grist for ' + url
  try
    res = HTTP.call 'GET', url
    return { total: res.data.HitCount, data: (res.data.RecordList?.Record ? {})}
  catch err
    return { status: 'error', data: 'Grist API GET failed', error: err }



API.use.grist.test = (verbose) ->
  console.log('Starting grist test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.grist = API.use.grist.grant_id '097410'
      return _.isEqual result.grist.data, API.use.grist.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending grist test') if API.settings.dev

  return result

API.use.grist.test._examples = {
  record: {
    "Person": {
      "FamilyName": "Newell",
      "GivenName": "Marie",
      "Initials": "ML",
      "Title": "Professor",
      "Alias": [
        {
          "@Source": "MRC",
          "$": "-268266"
        },
        {
          "@Source": "Wellcome Trust",
          "$": "82284"
        }
      ]
    },
    "Grant": {
      "Funder": {
        "Name": "Wellcome Trust",
        "pubMedSearchTerm": "Wellcome Trust"
      },
      "FundRefID": "http://dx.doi.org/10.13039/100004440",
      "Id": "097410",
      "Title": "Africa Centre for Health and Population Studies: Core Award",
      "Abstract": {
        "@Type": "scientific",
        "@Language": "en",
        "$": "No Data Entered"
      },
      "Type": "Major Overseas Programme",
      "Stream": "Populations and Public Health",
      "StartDate": "2012-10-01",
      "EndDate": "2017-09-30",
      "Amount": {
        "@Currency": "GBP",
        "$": "13526338"
      }
    },
    "Institution": {
      "Name": "University Of Kwazulu Natal"
    }
  }
}