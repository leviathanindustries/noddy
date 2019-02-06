
import gramophone from 'gramophone'
import CryptoJS from 'crypto-js' # TODO no need for this when crypto is available, fix below then remove
import crypto from 'crypto'

# TODO check out nodenatural and add it in here where useful
# https://github.com/NaturalNode/natural#tf-idf
# ALSO use the stopword package to strip stopwords from any text that needs processing
# https://www.npmjs.com/package/stopword

API.tdm = {}

API.add 'tdm/levenshtein',
	get: () ->
		if this.queryParams.a and this.queryParams.b
			return API.tdm.levenshtein this.queryParams.a, this.queryParams.b
		else
			return {data:'provide two query params called a and b which should be strings, get back the levenshtein distance'}

API.add 'tdm/categorise',
	get: () ->
		if this.queryParams.entity
			return API.tdm.categorise this.queryParams.entity
		else
			return {data: 'entity url param required'}

API.add 'tdm/keywords',
	get: () ->
		content = this.queryParams.content
		if this.queryParams.url
			url = this.queryParams.url
			url = 'http://' + url if url.indexOf('http') is -1
			if this.queryParams.format is 'text'
				content = HTTP.call('GET',url).content
			else if this.queryParams.format is 'pdf' or url.toLowerCase().indexOf('.pdf') isnt -1
				content = API.convert.pdf2txt url
			else
				content = API.convert.xml2txt url
		opts = {
			score: this.queryParams.score, # include frequency scores, or just list of terms, default false
			cutoff: this.queryParams.cutoff, # number between 0 and 1, bigger number means words inside sentences less likely to appear separately, default 0.5
			limit: this.queryParams.limit, # max number of terms to return, default unlimited
			stem: this.queryParams.stem, # do stemming first or not, default false
			min: this.queryParams.min, # min number of occurrences to be included, default 2
			len: this.queryParams.len, # shortest string to allow in answers, default 2
			flatten: this.queryParams.flatten # flatten results list, useful for feeding in to tf-idf later, default false
		}
		if this.queryParams.stopWords?
			opts.stopWords = this.queryParams.stopWords.split(',') # add stop words to the standard list
		opts.stopWords ?= ['s']
		opts.stopWords.push('s') if 's' not in opts.stopWords # analysis splits on things like word's, where ' becomes a space, leading to s as a word. So always ignore that
		if this.queryParams.ngrams
			if this.queryParams.ngrams.indexOf(',') isnt -1
				opts.ngrams = this.queryParams.ngrams.split(',')
				ngrams = []
				ngrams.push(parseInt(n)) for n in opts.ngrams
				opts.ngrams = ngrams
			else
				opts.ngrams = parseInt(this.queryParams.ngrams)
		return if content? then API.tdm.keywords(content,opts) else {}

API.add 'tdm/extract',
	get: () ->
		params = this.bodyParams
		params.url ?= this.queryParams.url
		params.url = 'http://' + params.url if params.url.indexOf('http') is -1
		if this.queryParams.match
			dm = decodeURIComponent(this.queryParams.match)
			params.matchers = if dm.indexOf(',') isnt -1 then dm.split(',') else [dm]
		params.lowercase = this.queryParams.lowercase?
		params.ascii = this.queryParams.ascii?
		params.convert ?= this.queryParams.convert
		params.start ?= this.queryParams.start
		params.end ?= this.queryParams.end
		return API.tdm.extract params

API.add 'tdm/difference/:str',
	get: () ->
		return API.tdm.difference this.urlParams.str.split(',')[0], this.urlParams.str.split(',')[1]



# http://stackoverflow.com/questions/4009756/how-to-count-string-occurrence-in-string
API.tdm.occurrence = (content, sub, overlap) ->
	content += ""
	sub += ""
	return (content.length + 1) if sub.length <= 0
	n = 0
	pos = 0
	step = if overlap then 1 else sub.length
	while true
		pos = content.indexOf sub, pos
		if pos >= 0
			++n
			pos += step
		else break
	return n

API.tdm.levenshtein = (a,b) ->
	minimator = (x, y, z) ->
		return x if x <= y and x <= z
		return y if y <= x and y <= z
		return z

	cost
	m = a.length
	n = b.length

	if m < n
		c = a
		a = b
		b = c
		o = m
		m = n
		n = o

	r = [[]]
	c = 0
	while c < n + 1
		c++
		r[0][c] = c

	i = 1
	while i < m + 1
		i++
		r[i] = [i]
		j = 1
		while j < n + 1
			j++
			cost = if a.charAt( i - 1 ) is b.charAt( j - 1 ) then 0 else 1
			r[i][j] = minimator( r[i-1][j] + 1, r[i][j-1] + 1, r[i-1][j-1] + cost )

	dist = r[ r.length - 1 ][ r[ r.length - 1 ].length - 1 ]
	return distance:dist,detail:r

API.tdm.categorise = (entity) ->
	exists = API.http.cache entity, 'tdm_categorise'
	return exists if exists

	rec = API.use.wikipedia.lookup {title:entity}
	return rec if rec.status is 'error'
	tidy = rec.data.revisions[0]['*'].toLowerCase().replace(/http.*?\.com\//g,'').replace(/\|accessdate.*?<\/ref>/g,'').replace(/<ref.*?\|url/g,'').replace(/access\-date.*?<\/ref>/g,'').replace(/file.*?]]/g,'')
	stops = ['http','https','ref','html','www','ref','cite','url','title','date','state','s','t','nbsp',
		'year','time','a','e','i','o','u','january','february','march','april','may','june','july','august','september','october','november','december',
		'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec',
		'news','work','post','times','york','category','newspaper','story','first1','first2','last1','last2','publisher',
		'general','world','list','org','id','wp','main','website','blogs','media','people','years','made','location',
		'accessdate','view_news','php','d0','dq','p','sfnref','false','true','onepage','article','chapter','book',
		'sfn','caps','authorlink','isbn']
	tp = entity.split(' ')
	stops.push(t.toLowerCase()) for t in tp
	tdm = API.tdm.keywords tidy,
		stopWords: stops
		min: 3
		limit: 50
		ngrams: [1,2,3,4]
		cutoff: 0
	keywords = []
	for a in tdm
		if keywords.length < 20 and a.replace(/[^ ]/g,'').length <= 2 and keywords.indexOf(a) is -1 and a.length > 1
			replace = false
			for kk of keywords
				if keywords[kk].indexOf(a) is 0
					replace = kk
			if replace is false
				keywords.push a
			else
				keywords[replace] = a

	url = 'https://en.wikipedia.org/wiki/' + rec.data.title.replace(/ /g,'_')
	if rec.data.pageprops
		img = rec.data.pageprops.page_image_free
		img ?= rec.data.pageprops.page_image
		if img?
			imghash = CryptoJS.MD5(img).toString() # TODO use crypto instead of crypto-js here
			img = 'https://upload.wikimedia.org/wikipedia/commons/' + imghash.charAt(0) + '/' + imghash.charAt(0) + imghash.charAt(1) + '/' + img
		wikibase = rec.data.pageprops.wikibase_item
		wikidata = if wikibase then 'https://www.wikidata.org/wiki/' + wikibase else undefined
	res = {url:url,img:img,title:rec.data.title,wikibase:wikibase,wikidata:wikidata,keywords:keywords}

	API.http.cache entity, 'tdm_categorise', res
	return res

API.tdm.keywords = (content,opts={}) ->
	opts.checksum = crypto.createHash('md5').update(content, 'utf8').digest('base64')
	opts.len ?= 2
	try opts.cutoff = (opts.cutoff*100000)/100000 if opts.cutoff? and typeof opts.cutoff isnt 'number'
	exists = API.http.cache opts, 'tdm_keywords'
	return exists if exists
	keywords = gramophone.extract content, opts
	res = []
	if opts
		for i in keywords
			str = if opts.score then i.term else i
			res.push i if (not opts.len or str.length >= opts.len) and (not opts.max or str.length <= opts.max)
	else
		res = keywords
	API.http.cache opts, 'tdm_keywords', res
	return res

API.tdm.extract = (opts) ->
	# opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
	opts.content = API.http.puppeteer(opts.url, true) if opts.url and not opts.content
	try
		text = if opts.convert then API.convert.run(opts.url ? opts.content, opts.convert, 'txt') else opts.content
	catch
		text = opts.content

	opts.matchers ?= [opts.match]
	if opts.start?
		parts = text.split opts.start
		text = if parts.length > 1 then parts[1] else parts[0]
	text = text.split(opts.end)[0] if opts.end?
	text = text.toLowerCase() if opts.lowercase
	text = text.replace(/[^a-z0-9]/g,'') if opts.ascii

	res = {matched:0,matches:[],matchers:opts.matchers}

	if text and typeof text isnt 'number'
		for match in opts.matchers
			mopts = 'g'
			mopts += 'i' if opts.lowercase
			if match.indexOf('/') is 0
				lastslash = match.lastIndexOf '/'
				if lastslash+1 isnt match.length
					mopts = match.substring lastslash+1
					match = match.substring 1,lastslash
			else
				match = match.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&")
			m
			mr = new RegExp match,mopts
			while m = mr.exec(text)
				res.matched += 1
				res.matches.push {matched:match,result:m}

	return res



