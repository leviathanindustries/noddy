
# https://dev.loklak.org/server/development/api.html#api-search-json

# term1 term2       : term1 and term2 shall appear in the Tweet text
# @user             : the user must be mentioned in the message
# from:user         : only messages published by the user
# #hashtag          : the message must contain the given hashtag
# near:<location>   : messages shall be created near the given location
# since:<date>      : only messages after the date (including the date), <date>=yyyy-MM-dd or yyyy-MM-dd_HH:mm
# until:<date>      : only messages before the date (excluding the date), <date>=yyyy-MM-dd or yyyy-MM-dd_HH:mm

# count           = <result count>                              // default 100, i.e. count=100, the wanted number of results
# source          = <cache|backend|twitter|all>                 // the source for the search, default all, i.e. source=cache
# fields          = <field name list, separated by ','>         // aggregation fields for search facets, like "created_at,mentions"
# limit           = <maximum number of facets for each field>   // a limitation of number of facets for each aggregation
# timezoneOffset  = <offset in minutes>                         // offset applied on since:, until: and the date histogram
# minified        = <true|false>                                // minify the result, default false, i.e. minified=true

API.use ?= {}
API.use.loklak = {}

API.add 'use/loklak/search',
  get: () -> return API.use.loklak.search this.queryParams


API.use.loklak.search = (params, timeout=API.settings.use?.loklak?.timeout ? API.settings.use?._timeout ? 10000) ->
  url = 'https://api.loklak.org/api/search.json?'
  for p of params
    url += (if p is 'from' then 'startRecord' else if p is 'size' then 'count' else p) + '=' + encodeURIComponent(if p is 'q' then params[p].replace(/ /g,'+') else if p is 'startRecord' then parseInt(params[p]) + 1 else params[p]) + '&'
  API.log 'Using loklak for ' + url
  try
    res = HTTP.call 'GET', url, {timeout:timeout}
    return if res.statusCode is 200 then { total: res.data.search_metadata.hits, data: res.data.statuses} else { status: 'error', data: res}
  catch err
    return {status: 'error', error: err.toString()}


###API.use.loklak.get = (q) ->
  res = API.http.cache q, 'loklak_get'
  if not res?
    ret = API.use.loklak.search qrystr
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
  return res###
