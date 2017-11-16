
# a simple way for any endpoint (probably the use endpoints) to cache
# results. e.g. if the use/europepmc submits a query to europepmc, it could
# cache the entire result, then check for a cached result on the next time
# it runs the same query. This is probably most useful for queries that
# expect to return singular result objects rather than full search lists

# the lookup value should be a stringified representation of whatever
# is being used as a query. It could be a JSON object or a URL, or so on.
# It will just get stringified and used to lookup later.

API.cache = {}

API.cache.save = (lookup,type='cache',content) ->
  return false if API.settings.cache is false
  cc = new API.collection index: API.settings.es.name + "_cache", type: type
  lookup = JSON.stringify(lookup) if typeof lookup not in ['string','number']
  if typeof content is 'string'
    try
      cc.insert lookup: lookup, string: content
    catch
      return false
  else
    try
      cc.insert lookup: lookup, content: content
      return true
    catch
      try
        cc.insert lookup: lookup, string: JSON.stringify(content)
        return true
      catch
        return false

API.cache.get = (lookup,type='cache',refresh=0,limit) ->
  return undefined if API.settings.cache is false
  cc = new API.collection index: API.settings.es.name + "_cache", type: type
  try
    lookup = JSON.stringify(lookup) if typeof lookup not in ['string','number']
    fnd = {"lookup.exact": lookup}
    if typeof refresh is 'number' and refresh isnt 0
      d = new Date()
      fnd = 'lookup.exact:"' + lookup + '" AND createdAt:>' + d.setDate(d.getDate() - refresh)
    res = cc.find fnd, true
    if res?.string?
      try
        API.log {msg:'Returning parsed string result from cache', lookup:lookup, type:type}
        return JSON.parse res.string
      catch
        API.log {msg:'Returning string result from cache', lookup:lookup, type:type}
        return res.string
    else if res?.content?
      API.log {msg:'Returning object content result from cache', lookup:lookup, type:type}
      return res.content
  # if nothing was found in cache, try to get the original if lookup is a URL
  # and cache it for next time, if we do get it
  if lookup.indexOf('http') is 0 or limit?
    try
      limit = {limit:limit} if typeof limit is 'number'
      if typeof limit?.limit is 'number'
        limit.fname ?= 'HTTP.call' if lookup.indexOf('http') is 0
        limit.args ?= ['GET',lookup] if lookup.indexOf('http') is 0
        limit.group ?= type if type isnt 'cache'
        res = API.job.limit limit.limit, limit.fname, limit.args, limit.group
      else
        res = HTTP.call 'GET', lookup
      if not res.statusCode? or res.statusCode is 200
        try API.cache.save lookup, (if res.content? then res.content else res)
        return (if res.content? then res.content else res)
      else
        return {status: 'error', data: res}
    catch err
      return {status: 'error', error: err.toString()}
  else
    return undefined
