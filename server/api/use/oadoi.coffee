
API.use ?= {}
API.use.oadoi = {}

API.add 'use/oadoi/:doipre/:doipost',
  get: () -> return API.use.oadoi.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.use.oadoi.doi = (doi) ->
  url = 'https://api.oadoi.org/v2/' + doi + '?email=mark@cottagelabs.com'
  API.log 'Using oadoi for ' + url
  res = API.cache.get doi, 'oadoi_doi'
  if not res?
    try
      res = HTTP.call 'GET', url
      if res.statusCode is 200
        res = res.data
        op = API.use.oadoi.open res, true
        res.open = op.open
        res.blacklist = op.blacklist
        API.cache.save doi, 'oadoi_doi', res
        return res
      else
        return undefined
    catch
      return undefined
  else
    return res

API.use.oadoi.open = (record,blacklist) ->
  res = {open: record?.best_oa_location?.url}
  if res.open?
    try
      resolves = HTTP.call 'HEAD', res.open
    catch
      res.open = undefined
  res.blacklist = API.service.oab?.blacklist(res.open) if res.open and blacklist
  return if blacklist then res else (if res.open then res.open else false)
