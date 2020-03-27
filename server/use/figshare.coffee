

# https://docs.figshare.com/api/#searching-filtering-and-pagination
# https://docs.figshare.com/#figshare_documentation_api_description_searching_filtering_and_pagination

API.use ?= {}
API.use.figshare = {}

API.add 'use/figshare/search', get: () -> return API.use.figshare.search this.queryParams, this.queryParams.format?

API.add 'use/figshare/doi/:doipre/:doipost',
  get: () -> return API.use.figshare.doi this.urlParams.doipre + '/' + this.urlParams.doipost, this.queryParams.format?


API.use.figshare.doi = (doi,format) ->
  res = API.http.cache doi, 'figshare_doi'
  if not res?
    res = API.use.figshare.search {search_for:doi}
    if res.data?.length and res.data[0].doi is doi
      res = res.data[0]
      res.url = res.url_public_html
      API.http.cache doi, 'figshare_doi', res
    else
      return undefined
  res.redirect = API.service.oab.redirect(res.url) if res?.url? and API.service.oab?
  return if format then API.use.figshare.format(res) else res

API.use.figshare.search = (params,format) ->
  # https://docs.figshare.com/#articles_search
  params = {search_for: params} if typeof params is 'string'
  if params?.q?
    params.search_for = params.q
    delete params.q
  if params.format?
    delete params.format
    format ?= true
  params.order ?= 'published_date' # order default depends on resource. For articles, can be published_date, modified_date
  params.order_direction ?= 'desc' # order_direction asc or desc
  params.page_size ?= params.size ? 100 # page_size or limit default 10, max 1000
  # page int 1 can be page number, for size of 10, max is 100
  # offset int	0	Where to start the listing(the offset of the first result), limit 1000
  url = 'https://api.figshare.com/v2/articles/search'
  API.log 'Using figshare for ' + url
  # search_for is required
  try
    res = HTTP.call 'POST', url, {data:params,headers:{'Content-Type':'application/json'}}
    if res.statusCode is 200
      if format
        for d of res.data
          res.data[d] = API.use.figshare.format res.data[d]
      return data: res.data
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', data: 'figshare API error', error: err}

API.use.figshare.published = (startdate,params,format) ->
  # can also use "published_since": "2017-12-22"
  params.published_since ?= startdate
  return API.use.figshare.search params, format

API.use.figshare.format = (rec, metadata={}) ->
  try metadata.title ?= rec.title
  try metadata.doi ?= rec.doi
  try metadata.published ?= rec.published_date.split('T')[0]
  try metadata.year ?= metadata.published.split('-')[0]
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  try metadata.open ?= rec.open
  try metadata.redirect ?= rec.redirect
  return metadata

