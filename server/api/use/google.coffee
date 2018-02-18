

import fs from 'fs'
# docs:
# https://developers.google.com/places/web-service/autocomplete
# example:
# https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Aberdeen%20Asset%20Management%20PLC&key=<OURKEY>

API.use ?= {}
API.use.google = {places:{},docs:{},sheets:{},cloud:{},knowledge:{}}

API.add 'use/google/places/autocomplete',
  get: () -> return API.use.google.places.autocomplete this.queryParams.q,this.queryParams.location,this.queryParams.radius

API.add 'use/google/places/place',
  get: () -> return API.use.google.places.place this.queryParams.id,this.queryParams.q,this.queryParams.location,this.queryParams.radius

API.add 'use/google/places/nearby',
  get: () -> return API.use.google.places.nearby this.queryParams

API.add 'use/google/places/search',
  get: () -> return API.use.google.places.search this.queryParams

API.add 'use/google/places/url',
  get: () -> return API.use.google.places.url this.queryParams.q

API.add 'use/google/language',
  get:
    roleRequired:'root'
    action: () -> return API.use.google.cloud.language this.queryParams.content,this.queryParams.actions

API.add 'use/google/language/:what',
  get:
    roleRequired:'root'
    action: () -> return API.use.google.cloud.language this.queryParams.content,[this.urlParams.what]

API.add 'use/google/knowledge/retrieve/:letter/:id',
  get:
    roleRequired:'root'
    action: () ->
      return API.use.google.knowledge.retrieve '/' + this.urlParams.letter + '/' + this.urlParams.id,this.queryParams.types,this.queryParams.wikidata

API.add 'use/google/knowledge/search',
  get:
    roleRequired:'root'
    action: () -> return API.use.google.knowledge.search this.queryParams.q,this.queryParams.limit

API.add 'use/google/clear',
  get: () ->
    # TODO this would really need a way to send a clear cache signal across all cluster instances - maybe use the job runner
    removed = []
    if fs.existsSync '.googlelocalcopy'
      fs.readdirSync('.googlelocalcopy').forEach (file, index) ->
        fs.unlinkSync ".googlelocalcopy/" + file
        removed.push file
    return removed



# TODO add old deprecated google finance API, if useful for anything. Runs 15 mins delay
# see http://finance.google.com/finance/info?client=ig&q=NASDAQ:AAPL
# which runs pages lik https://finance.yahoo.com/quote/AAPL/profile

# https://developers.google.com/knowledge-graph/
# https://developers.google.com/knowledge-graph/reference/rest/v1/
API.use.google.knowledge.retrieve = (mid,types,wikidata) ->
  u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=1&ids=' + mid
  if types
    types = types.join('&types=') if typeof types isnt string # are multiple types done by comma separation or key repetition?
    u += '&types=' + types
  ret = {}
  try
    res = HTTP.call 'GET',u
    ret = res.data.itemListElement[0].result
    ret.score = res.data.itemListElement[0].resultScore
    if wikidata
      ret.wikidata = API.use.google.knowledge.wikidata ret["@id"].replace('kg:',''), ret.detailedDescription.url
  return ret

API.use.google.knowledge.search = (qry,limit=10) ->
  u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=' + limit + '&query=' + qry
  return HTTP.call('GET',u).data

API.use.google.knowledge.wikidata = (mid,wurl) ->
  if mid and not wurl
    k = API.use.google.knowledge.retrieve mid
    wurl = k.detailedDescription?.url
  if wurl
    return API.use.wikidata.find undefined,wurl

# https://cloud.google.com/natural-language/docs/getting-started
# https://cloud.google.com/natural-language/docs/basics
API.use.google.cloud.language = (content, actions=['entities','sentiment'], auth) ->
  actions = actions.split(',') if typeof actions is 'string'
  return {} if not content?
  lurl = 'https://language.googleapis.com/v1/documents:analyzeEntities?key=' + API.settings.use.google.serverkey
  document = {document: {type: "PLAIN_TEXT",content:content},encodingType:"UTF8"}
  if 'entities' in actions
    try return entities: HTTP.call('POST',lurl,{data:document,headers:{'Content-Type':'application/json'}}).data.entities
  if 'sentiment' in actions
    try return sentiment: HTTP.call('POST',lurl.replace('analyzeEntities','analyzeSentiment'),{data:document,headers:{'Content-Type':'application/json'}}).data

API.use.google.places.autocomplete = (qry,location,radius) ->
  url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=' + qry + '&key=' + API.settings.use.google.serverkey
  url += '&location=' + location + '&radius=' + (radius ? '10000') if location?
  try
    return HTTP.call('GET',url).data
  catch err
    return {status:'error', error: err}

API.use.google.places.place = (id,qry,location,radius) ->
  if not id?
    try
      results = API.use.google.places.autocomplete qry,location,radius
      id = results.predictions[0].place_id
    catch err
      return {status:'error', error: err}
  url = 'https://maps.googleapis.com/maps/api/place/details/json?placeid=' + id + '&key=' + API.settings.use.google.serverkey
  try
    return HTTP.call('GET',url).data
  catch err
    return {status:'error', error: err}

API.use.google.places.url = (qry) ->
  try
    results = API.use.google.places.place undefined,qry
    return {data: {url:results.result.website.replace('://','______').split('/')[0].replace('______','://')}}
  catch err
    return {status:'error', error: err}

API.use.google.places.nearby = (params={}) ->
  url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
  params.key ?= API.settings.use.google.serverkey
  url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
  try
    return HTTP.call('GET',url).data
  catch err
    return {status:'error', error: err}

API.use.google.places.search = (params) ->
  url = 'https://maps.googleapis.com/maps/api/place/textsearch/json?'
  params.key ?= API.settings.use.google.serverky
  url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
  try
    return HTTP.call('GET',url).data
  catch err
    return {status:'error', error: err}

API.use.google.sheets.feed = (sheetid,stale=3600000) ->
  return [] if not sheetid?
  # expects a google sheet ID or a URL to a google sheets feed in json format
  # NOTE the sheet must be published for this to work, should have the data in sheet 1, and should have columns of data with key names in row 1
  url = if sheetid.indexOf('http') isnt 0 then 'https://spreadsheets.google.com/feeds/list/' + sheetid + '/od6/public/values?alt=json' else sheetid
  sheetid = sheetid.replace('https://','').replace('http://','').replace('spreadsheets.google.com/feeds/list/','').split('/')[0]
  localcopy = '.googlelocalcopy/' + sheetid + '.json'
  values = []
  if fs.existsSync(localcopy) and ((new Date()) - fs.statSync(localcopy).mtime) < stale
    values = JSON.parse fs.readFileSync(localcopy)
  else
    try
      API.log 'Getting google sheet from ' + url
      g = HTTP.call('GET',url)
      list = g.data.feed.entry
      for l of list
        val = {}
        for k of list[l]
          try val[k.replace('gsx$','')] = list[l][k].$t if k.indexOf('gsx$') is 0
        values.push val
    fs.mkdirSync('.googlelocalcopy') if not fs.existsSync '.googlelocalcopy'
    fs.writeFileSync localcopy, JSON.stringify(values)
  return values


