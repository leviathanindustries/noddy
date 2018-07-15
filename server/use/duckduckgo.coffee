
# duckduckgo instant answers API
# docs:
# https://duckduckgo.com/api
# 
# example:
# http://api.duckduckgo.com/?q=abcam&format=json

# looks like duckduckgo block multiple requests from backend servers, as they said they might

API.add 'use/duckduckgo', get: () -> return {info: 'A wrap of the duckduckgo API - it works, but they DO block. Not sure what counts as blockable usage yet...'} 

API.add 'use/duckduckgo/instants', get: () -> API.use.duckduckgo.instants this.queryParams.q



API.use ?= {}
API.use.duckduckgo = {}

API.use.duckduckgo.instants = (qry,service='noddy') ->
  url = 'https://api.duckduckgo.com/?q=' + qry + '&format=json&t=' + service
  API.log 'Using duckduckgo to query ' + url
  try
    return HTTP.call('GET',url).data
  catch err
    return {status:'error', error: err}


