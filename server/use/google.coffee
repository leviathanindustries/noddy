
import fs from 'fs'
# docs:
# https://developers.google.com/places/web-service/autocomplete
# example:
# https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Aberdeen%20Asset%20Management%20PLC&key=<OURKEY>

API.use ?= {}
API.use.google = {search:{},places:{},docs:{},sheets:{},cloud:{},knowledge:{}}

API.add 'use/google/places/autocomplete',
	get: () -> return API.use.google.places.autocomplete this.queryParams.q,this.queryParams.location,this.queryParams.radius

API.add 'use/google/places/place',
	get: () -> return API.use.google.places.place this.queryParams.id,this.queryParams.q,this.queryParams.location,this.queryParams.radius

API.add 'use/google/places/nearby', get: () -> return API.use.google.places.nearby this.queryParams

API.add 'use/google/places/search', get: () -> return API.use.google.places.search this.queryParams

API.add 'use/google/places/url', get: () -> return API.use.google.places.url this.queryParams.q

API.add 'use/google/search/custom', 
	get:
		roleRequired:'root'
		action: () -> return API.use.google.search.custom this.queryParams.q

API.add 'use/google/language',
	get:
		roleRequired:'root'
		action: () ->
			if this.queryParams.url? and not this.queryParams.content?
				url = this.queryParams.url
				url = 'http://' + url if url.indexOf('http') is -1
				if this.queryParams.format is 'text'
					this.queryParams.content = HTTP.call('GET',url).content
				else if this.queryParams.format is 'pdf' or url.toLowerCase().indexOf('.pdf') isnt -1
					this.queryParams.content = API.convert.pdf2txt url
				else
					this.queryParams.content = API.convert.xml2txt url
			return if not this.queryParams.content? then {} else API.use.google.cloud.language this.queryParams.content,this.queryParams.actions

API.add 'use/google/language/:what',
	get:
		roleRequired:'root'
		action: () ->
			if this.queryParams.url? and not this.queryParams.content?
				url = this.queryParams.url
				url = 'http://' + url if url.indexOf('http') is -1
				if this.queryParams.format is 'text'
					this.queryParams.content = HTTP.call('GET',url).content
				else if this.queryParams.format is 'pdf' or url.toLowerCase().indexOf('.pdf') isnt -1
					this.queryParams.content = API.convert.pdf2txt url
				else
					this.queryParams.content = API.convert.xml2txt url
			return if not this.queryParams.content? then {} else API.use.google.cloud.language this.queryParams.content,[this.urlParams.what]

API.add 'use/google/translate',
	get:
		roleRequired:'root'
		action: () ->
			return API.use.google.cloud.translate this.queryParams.q, this.queryParams.source, this.queryParams.target, this.queryParams.format

API.add 'use/google/knowledge/retrieve/:letter/:id',
	get:
		roleRequired:'root'
		action: () ->
			return API.use.google.knowledge.retrieve '/' + this.urlParams.letter + '/' + this.urlParams.id,this.queryParams.types,this.queryParams.wikidata

API.add 'use/google/knowledge/search',
	get:
		roleRequired:'root'
		action: () -> return API.use.google.knowledge.search this.queryParams.q,this.queryParams.limit

API.add 'use/google/knowledge/find',
	get:
		roleRequired:'root'
		action: () -> return API.use.google.knowledge.find this.queryParams.q

API.add 'use/google/sheets/:sheetid', get: () -> return API.use.google.sheets.feed this.urlParams.sheetid, this.queryParams
API.add 'use/google/sheets/api/:sheetid', get: () -> return API.use.google.sheets.api.get this.urlParams.sheetid, this.queryParams
API.add 'use/google/sheets/api/:sheetid/values', get: () -> return API.use.google.sheets.api.values this.urlParams.sheetid, this.queryParams

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



# https://developers.google.com/custom-search/json-api/v1/overview#Pricing
# note technically meant to be targeted to a site but can do full search on free tier
# free tier only up to 100 queries a day. After that, $5 per 1000, up to 10k
API.use.google.search.custom = (q, id=API.settings.use.google.search.id, key=API.settings.use.google.search.key) ->
	url = 'https://www.googleapis.com/customsearch/v1?key=' + key + '&cx=' + id + '&q=' + q
	return API.http.proxy('GET',url,true).data

	
	
# https://developers.google.com/knowledge-graph/
# https://developers.google.com/knowledge-graph/reference/rest/v1/
API.use.google.knowledge.retrieve = (mid,types,wikidata) ->
	exists = API.http.cache {mid:mid,types:types,wikidata:wikidata}, 'google_knowledge_retrieve'
	return exists if exists
	u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=1&ids=' + mid
	if types
		types = types.join('&types=') if typeof types isnt 'string' # are multiple types done by comma separation or key repetition?
		u += '&types=' + types
	ret = {}
	try
		res = API.http.proxy 'GET', u, true
		ret = res.data.itemListElement[0].result
		ret.score = res.data.itemListElement[0].resultScore
		if wikidata
			ret.wikidata = API.use.google.knowledge.wikidata ret["@id"].replace('kg:',''), ret.detailedDescription.url
	if not _.isEmpty ret
		API.http.cache {mid:mid,types:types,wikidata:wikidata}, 'google_knowledge_retrieve', ret
	return ret

API.use.google.knowledge.search = (qry,limit=10,refresh=604800000) -> # default 7 day cache
	u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=' + limit + '&query=' + encodeURIComponent qry
	API.log 'Searching google knowledge for ' + qry

	checksum = API.job.sign qry
	exists = API.http.cache checksum, 'google_knowledge_search', undefined, refresh
	return exists if exists

	res = API.http.proxy('GET',u,true).data
	try API.http.cache checksum, 'google_knowledge_search', res
	return res

API.use.google.knowledge.find = (qry) ->
	res = API.use.google.knowledge.search qry
	try
		return res.itemListElement[0].result #could add an if resultScore > ???
	catch
		return undefined

API.use.google.knowledge.wikidata = (mid,wurl) ->
	# don't cache this, wikidata is cached
	res = {}
	if mid and not wurl
		k = API.use.google.knowledge.retrieve mid
		wurl = k.detailedDescription?.url
	if wurl
			w = API.use.wikipedia.lookup {title:wurl.split('wiki/').pop()}
			res.qid = w.data?.pageprops?.wikibase_item
			res.data = API.use.wikidata.get(res.qid) if res.qid?
	return res



# https://cloud.google.com/natural-language/docs/getting-started
# https://cloud.google.com/natural-language/docs/basics
API.use.google.cloud.language = (content, actions=['entities','sentiment'], auth) ->
	actions = actions.split(',') if typeof actions is 'string'
	return {} if not content?
	checksum = API.job.sign content, actions
	exists = API.http.cache checksum, 'google_language'
	return exists if exists

	lurl = 'https://language.googleapis.com/v1/documents:analyzeEntities?key=' + API.settings.use.google.serverkey
	document = {document: {type: "PLAIN_TEXT",content:content},encodingType:"UTF8"}
	result = {}
	if 'entities' in actions
		try result.entities = API.http.proxy('POST',lurl,{data:document,headers:{'Content-Type':'application/json'}},true).data.entities
	if 'sentiment' in actions
		try result.sentiment = API.http.proxy('POST',lurl.replace('analyzeEntities','analyzeSentiment'),{data:document,headers:{'Content-Type':'application/json'}},true).data
	API.http.cache(checksum, 'google_language', result) if not _.isEmpty result
	return result

# https://cloud.google.com/translate/docs/quickstart
API.use.google.cloud.translate = (q, source, target='en', format='text') ->
	# ISO source and target language codes
	# https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
	return {} if not q?
	checksum = API.job.sign q, {source: source, target: target, format: format}
	exists = API.http.cache checksum, 'google_translate'
	return exists if exists
	lurl = 'https://translation.googleapis.com/language/translate/v2?key=' + API.settings.use.google.serverkey
	result = API.http.proxy('POST', lurl, {data:{q:q, source:source, target:target, format:format}, headers:{'Content-Type':'application/json'}},true)
	if result?.data?.data?.translations
		res = result.data.data.translations[0].translatedText
		API.http.cache(checksum, 'google_language', res) if res.length
		return res
		#return result.data.data
	else
		return {}



API.use.google.places.autocomplete = (qry,location,radius) ->
	url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=' + qry + '&key=' + API.settings.use.google.serverkey
	url += '&location=' + location + '&radius=' + (radius ? '10000') if location?
	try
		return API.http.proxy('GET',url,true).data
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
		return API.http.proxy('GET',url,true).data
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
		return API.http.proxy('GET',url,true).data
	catch err
		return {status:'error', error: err}

API.use.google.places.search = (params) ->
	url = 'https://maps.googleapis.com/maps/api/place/textsearch/json?'
	params.key ?= API.settings.use.google.serverkey
	url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
	try
		return API.http.proxy('GET',url,true).data
	catch err
		return {status:'error', error: err}



API.use.google.sheets.feed = (sheetid, opts={}) ->
	opts = {stale:opts} if typeof opts is 'number'
	opts.stale = opts.refresh if opts.refresh?
	opts.stale ?= 3600000
	opts.sheet ?= 'default' # or else a number, starting from 1, indicating which sheet in the overall sheet to access
	return [] if not sheetid?
	# expects a google sheet ID or a URL to a google sheets feed in json format
	# NOTE the sheet must be published for this to work, should have the data in sheet 1, and should have columns of data with key names in row 1
	sheetid = sheetid.split('/spreadsheets/d/')[1].split('/')[0] if sheetid.indexOf('http') is 0 and sheetid.indexOf('/spreadsheets/d/') isnt -1 and sheetid.indexOf('/feeds/list/') is -1
	url = if sheetid.indexOf('http') isnt 0 then 'https://spreadsheets.google.com/feeds/list/' + sheetid + '/' + opts.sheet + '/public/values?alt=json' else sheetid
	sheetid = sheetid.replace('https://','').replace('http://','').replace('spreadsheets.google.com/feeds/list/','').split('/')[0]
	localcopy = '.googlelocalcopy/' + sheetid + (if opts.sheet isnt 'default' then '_' + opts.sheet else '') + '.json'
	values = []
	if fs.existsSync(localcopy) and ((new Date()) - fs.statSync(localcopy).mtime) < opts.stale
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
		if values.length
			console.log values.length
			fs.mkdirSync('.googlelocalcopy') if not fs.existsSync '.googlelocalcopy'
			fs.writeFileSync localcopy, JSON.stringify(values)
	return values



API.use.google.sheets.api = {}
# https://developers.google.com/sheets/api/reference/rest
API.use.google.sheets.api.get = (sheetid, opts={}) ->
	opts = {stale:opts} if typeof opts is 'number'
	opts.stale ?= 3600000
	opts.key ?= API.settings.use.google.serverkey
	try
		sheetid = sheetid.split('/spreadsheets/d/')[1].split('/')[0] if sheetid.indexOf('/spreadsheets/d/') isnt -1
		url = 'https://sheets.googleapis.com/v4/spreadsheets/' + sheetid
		url += '/values/' + opts.start + ':' + opts.end if opts.start and opts.end
		url += '?key=' + opts.key
		API.log 'Getting google sheet via API ' + url
		g = HTTP.call 'GET', url
		return g.data ? g
	catch err
		return err

API.use.google.sheets.api.values = (sheetid, opts={}) ->
	opts.start ?= 'A1'
	if not opts.end?
		sheet = if typeof sheetid is 'object' then sheetid else API.use.google.sheets.api.get sheetid, opts
		opts.sheet ?= 0 # could also be the ID or title of a sheet in the sheet... if so iterate them to find the matching one
		rows = sheet.sheets[opts.sheet].properties.gridProperties.rowCount
		cols = sheet.sheets[opts.sheet].properties.gridProperties.columnCount
		opts.end = ''
		ls = Math.floor cols/26
		opts.end += (ls + 9).toString(36).toUpperCase() if ls isnt 0
		opts.end += (cols + 9-ls).toString(36).toUpperCase()
		opts.end += rows
	values = []
	try
		keys = false
		res = API.use.google.sheets.api.get sheetid, opts
		opts.keys ?= 0 # always assume keys? where to tell which row to get them from? 0-indexed or 1-indexed or named?
		keys = opts.keys if Array.isArray opts.keys
		for s in res.values
			if opts.keys? and keys is false
				keys = s
			else
				obj = {}
				for k of keys
					try
						obj[keys[k]] = s[k] if s[k] isnt ''
				values.push(obj) if not _.isEmpty obj
	return values