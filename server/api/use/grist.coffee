

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
  url = 'http://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=' + qrystr + '&resultType=core&format=json'
  url += '&page=' + (Math.floor(from/GRIST_API_PAGE_SIZE)+1) if from?
  try
    res = HTTP.call 'GET', url
    return { total: res.data.HitCount, data: (res.data.RecordList?.Record ? {})}
  catch err
    return { status: 'error', data: 'Grist API GET failed', error: err }

