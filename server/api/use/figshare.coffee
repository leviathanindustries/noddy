
# https://docs.figshare.com/api/#searching-filtering-and-pagination

API.use ?= {}
API.use.figshare = {}

API.add 'use/figshare/search', get: () -> return API.use.figshare.search this.queryParams

API.add 'use/figshare/doi/:doipre/:doipost',
  get: () -> return API.use.figshare.doi this.urlParams.doipre + '/' + this.urlParams.doipost


API.use.figshare.doi = (doi) ->
  res = API.use.figshare.search {search_for:doi}
  if res.data?.length and res.data[0].doi is doi
    return {data: res.data[0]}
  else
    return {status:'error'}

API.use.figshare.search = (params) ->
  url = 'https://api.figshare.com/v2/articles/search'
  API.log 'Using figshare for ' + url
  # search_for is required
  try
    res = HTTP.call 'POST', url, {data:params,headers:{'Content-Type':'application/json'}}
    return if res.statusCode is 200 then { status: 'success', data: res.data} else { status: 'error', data: res}
  catch err
    return { status: 'error', data: 'figshare API error', error: err}
