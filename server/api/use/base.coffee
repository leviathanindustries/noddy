
# BASE provide a search endpoint, but must register our IP to use it first
# limited to non-commercial and 1 query per second, contact them for more options
# register here: https://www.base-search.net/about/en/contact.php (registered)
# docs here:
# http://www.base-search.net/about/download/base_interface.pdf

API.use ?= {}
API.use.base = {}

API.add 'use/base/search', get: () -> return API.use.base.search this.queryParams.q, this.queryParams.from, this.queryParams.size

API.add 'use/base/doi/:doipre/:doipost', get: () -> return API.use.base.doi this.urlParams.doipre+'/'+this.urlParams.doipost

API.use.base.doi = (doi) ->
	# TODO should simplify response down to just one result if possible
	# TODO should consider deref via crossref then doing title search on BASE instead, if not found by DOI
	# e.g. 10.1016/j.biombioe.2012.01.022 can be found in BASE with title but not with DOI
	# also note when simplifying title that titles from crossref can include xml in them
	# like https://dev.api.cottagelabs.com/use/crossref/works/doi/10.1016/j.cpc.2016.07.035
	# which has mathml in the title, perhaps put there by the publisher and not stripped by crossref, or put there by crossref
	return API.use.base.get doi

API.use.base.title = (title) ->
	simplify = /[\u0300-\u036F]/g
	title = title.toLowerCase().normalize('NFKD').replace(simplify,'').replace(/ß/g,'ss')
	ret = API.use.base.get('dctitle:"'+title+'"')
	return if ret.dctitle.toLowerCase().normalize('NFKD').replace(simplify,'').replace(/ß/g,'ss') is ret.title.toLowerCase() then ret else undefined

API.use.base.get = (qry) ->
	res = API.cache.get qry, 'base_get'
	if not res?
		res = API.use.base.search qry
		res = if res?.data?.docs?.length then res.data.docs[0] else undefined
		if res?
			op = API.use.base.open res, true
			res.open = op.open
			res.blacklist = op.blacklist
			API.cache.save qry, 'base_get', res
	return res

API.use.base.search = (qry='*',from,size) ->
	# it uses offset and hits (default 10) for from and size, and accepts solr query syntax
	# string terms, "" to be next to each other, otherwise ANDed, can accept OR, and * or ? wildcards, brackets to group, - to negate
	proxy = API.settings.proxy # need to route through the proxy so requests come from registered IP
	if not proxy
		API.log 'No proxy settings available to use BASE'
		return { data: 'NO BASE PROXY SETTING PRESENT!'}
	qry = qry.replace(/ /g,'+') if qry.indexOf('"') is -1 and qry.indexOf(' ') isnt -1
	url = 'http://api.base-search.net/cgi-bin/BaseHttpSearchInterface.fcgi?func=PerformSearch&format=json&query=' + qry
	url += '&offset=' + from if from
	url += '&hits=' + size if size
	API.log 'Using BASE for ' + url
	try
		res = HTTP.call 'GET', url, {npmRequestOptions:{proxy:proxy}}
		return if res.statusCode is 200 then {data: JSON.parse(res.content).response} else {data:res}
	catch err
		return { data: 'BASE API error', error: err.toString()}

API.use.base.open = (record,blacklist) ->
	res = {open: record.dclink}
	if res.open?
		try
			resolves = HTTP.call 'HEAD', res.open
		catch
			res.open = undefined
	res.blacklist = API.service.oab?.blacklist(res.open) if res.open and blacklist
	return if blacklist then res else (if res.open then res.open else false)
