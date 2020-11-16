
import fs from 'fs'

API.use ?= {}
API.use.ror = {}

@ror_record = new API.collection {index:"ror",type:"record"}



API.add 'use/ror', () -> return ror_record.search this
API.add 'use/ror/search', 
  csv: true
  get: () -> return if this.request.route.indexOf('.csv') isnt -1 and this.queryParams.all isnt true then API.use.ror.search(this.queryParams).data else API.use.ror.search this.queryParams
API.add 'use/ror/:rid', get: () -> return API.use.ror.get this.urlParams.rid
API.add 'use/ror/import', 
  get: () -> 
    Meteor.setTimeout (() => API.use.ror.import this.queryParams), 1
    return true



# https://api.ror.org/organizations?filter=country.country_code:US,types:Government
# there are about 100000 orgs in it so far
API.use.ror.search = (params={}, from=0, size=10) ->
  params = {filter: params} if typeof params is 'string'
  if params.all is true
    delete params.all
    return API.use.ror.batch params
  if params.q
    params.filter = params.q # valid filters have to be typed by key, like the example above
    delete params.q # q param not allowed by ror, don't know if there is a search param other than filter
  params.from ?= from
  params.size ?= size
  if params.from?
    # paging allowed from 1 to 500
    # page size is 20, don't know yet what the param for changing that is, but size is not allowed
    params.page ?= if params.from is 0 then 1 else Math.floor(params.from / params.size)+1 # ror uses page, not from and size (not sure if it uses size)
    delete params.from
    delete params.size
  url = 'https://api.ror.org/organizations?'
  url += p + '=' + params[p] + '&' for p of params
  API.log 'Getting ROR for ' + url
  res = HTTP.call 'GET', url
  return total: res.data.number_of_results, data: res.data.items, meta: res.data.meta # meta is facets/aggs sort of thing, with counts and lists
  
API.use.ror.get = (rid) ->
  # note the id field in searches above returns the id as a URL in ror.org with the ID at the end
  if lc = ror_record.get rid
    return lc
  else
    url = 'https://api.ror.org/organizations/' + rid
    API.log 'Getting ROR for ' + url
    return HTTP.call('GET', url).data

API.use.ror.batch = (params={}) ->
  params.page ?= 1
  results = []
  pages = false
  while pages is false or params.page <= pages
    res = API.use.ror.search params
    pages = Math.floor(res.total / 20)+1 if pages is false
    params.page += 1
    results = results.concat res.data
  return results
  
API.use.ror.import = () ->
  # needs a way to get a fresh file dump from ror.org which actually stores on figshare
  fl = '/home/cloo/ror/ror.json'
  recs = JSON.parse fs.readFileSync fl
  batch = []
  counter = 0
  for rec in recs
    rec._id = rec.id.split('/').pop()
    batch.push rec
    counter += 1
    if batch.length is 1000
      ror_record.insert batch
      batch = []
  if batch.length
    ror_record.insert batch
  return counter