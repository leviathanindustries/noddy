
# helps find email addresses
# https://hunter.io/api/docs

API.use ?= {}
API.use.hunter = {}

#API.add 'use/hunter/domain', get: () -> return API.use.hunter.domain this.queryParams

API.use.hunter.domain = (qp,api_key) ->
  api_key ?= API.settings?.use?.hunter?.api_key
  return undefined if not qp? or (not qp.domain? and not qp.company?) or not api_key?
  res = API.http.cache qp, 'hunter_domain'
  if not res?
    url = 'https://api.hunter.io/v2/domain-search?api_key=' + api_key # requires one of domain= or company='
    for p of params
      url += '&' + p + '=' + params[p]
    API.log 'Using hunter.io for ' + url
    try
      res = HTTP.call 'GET', url
      if res.statusCode is 200 and res.data?
        if res.data.emails? and res.data.emails.length
          API.http.cache qp, 'hunter_domain', res.data
        return res.data
      else
        return { status: 'error', data: res}
    catch err
      return { status: 'error', data: 'Hunter API error', error: err}
  else
    return res

API.use.hunter.email = (qp,api_key) ->
  api_key ?= API.settings?.use?.hunter?.api_key
  return undefined if not qp? or (not qp.domain? and not qp.company?) or (not qp.full_name or (not qp.first_name or not qp.last_name)) or not api_key?
  res = API.http.cache qp, 'hunter_email'
  if not res?
    url = 'https://api.hunter.io/v2/email-finder?api_key=' + api_key # requires one of domain= or company=' and either full_name or first and last name
    for p of params
      url += '&' + p + '=' + params[p]
    API.log 'Using hunter.io for ' + url
    try
      res = HTTP.call 'GET', url
      if res.statusCode is 200 and res.data?
        if res.data.email?
          API.http.cache qp, 'hunter_email', res.data
        return res.data
      else
        return { status: 'error', data: res}
    catch err
      return { status: 'error', data: 'Hunter API error', error: err}
  else
    return res

