
API.use ?= {}
API.use.oadoi = {}

API.add 'use/oadoi/:doipre/:doipost',
  get: () -> return API.use.oadoi.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.use.oadoi.doi = (doi,open) ->
  url = 'https://api.oadoi.org/v2/' + doi + '?email=mark@cottagelabs.com'
  API.log 'Using oadoi for ' + url
  try
    res = HTTP.call 'GET', url
    return if res.statusCode is 200 and (not open or API.use.oadoi.open(res.data)) then { data: res.data} else { status: 'error', data: res.data}
  catch err
    return 404

API.use.oadoi.open = (res) ->
  if bl = API.service.oab.blacklist(res.best_oa_location.url,true) isnt true
    return if bl then bl else res.best_oa_location.url
  else
    return false

  