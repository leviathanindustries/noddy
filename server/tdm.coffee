
import gramophone from 'gramophone'
import crypto from 'crypto'
import natural from 'natural'
import wordpos from 'wordpos'
import stopword from 'stopword'
import languagedetect from 'languagedetect'
import Future from 'fibers/future'
import pdfjs from 'pdfjs-dist'
import diff from 'diff'

# TODO check out nodenatural and add it in here where useful
# https://github.com/NaturalNode/natural#tf-idf
# ALSO use the stopword package to strip stopwords from any text that needs processing
# https://www.npmjs.com/package/stopword
# and have a look at wordpos too
# https://github.com/moos/wordpos

API.tdm = {}

API.add 'tdm/clean', get: () -> return API.tdm.clean this.queryParams.q

API.add 'tdm/diff', get: () -> return API.tdm.diff this.queryParams.a, this.queryParams.b, this.queryParams

API.add 'tdm/fulltext', 
  get: () -> 
    res = API.tdm.fulltext this.queryParams.url
    return if this.queryParams.verbose then res else res.fulltext

API.add 'tdm/levenshtein',
	get: () ->
		if this.queryParams.a and this.queryParams.b
			return API.tdm.levenshtein this.queryParams.a, this.queryParams.b, this.queryParams.lowercase
		else
			return {data:'provide two query params called a and b which should be strings, get back the levenshtein distance'}

API.add 'tdm/hamming',
	get: () ->
		if this.queryParams.a and this.queryParams.b
			return API.tdm.hamming this.queryParams.a, this.queryParams.b
		else
			return {data:'provide two query params called a and b which should be strings, get back the hamming distance'}

API.add 'tdm/language', get: () -> return API.tdm.language this.queryParams.q

API.add 'tdm/entities',
	get: () ->
		if this.queryParams.content
			return API.tdm.entities this.queryParams.content
		else if this.queryParams.url
			ft = API.tdm.fulltext this.queryParams.url
			return API.tdm.entities ft.fulltext, full: true
		else
			return {}

API.add 'tdm/categorise',
	get: () ->
		if this.queryParams.entity
			return API.tdm.categorise this.queryParams.entity
		else
			return {data: 'entity url param required'}

API.add 'tdm/isnumber', get: () -> return API.tdm.isnumber this.queryParams.q ? this.queryParams.number
API.add 'tdm/hasnumber', get: () -> return API.tdm.hasnumber this.queryParams.q ? this.queryParams.term
API.add 'tdm/word', get: () -> return API.tdm.word this.queryParams.q ? this.queryParams.word, this.queryParams.type, this.queryParams.shortnames?
API.add 'tdm/isword', get: () -> return API.tdm.isword this.queryParams.q ? this.queryParams.word, this.queryParams.type, this.queryParams.shortnames?
API.add 'tdm/stopwords', get: () -> return API.tdm.stopwords()
API.add 'tdm/words', 
	get: () ->
		content = this.queryParams.content
		if this.queryParams.url
			try content = API.tdm.fulltext(this.queryParams.url).fulltext
		return if typeof content is 'string' and content.length then API.tdm.words(content) else []

API.add 'tdm/keywords',
	get: () ->
		content = this.queryParams.content
		if this.queryParams.url
			url = this.queryParams.url
			url = 'http://' + url if url.indexOf('http') is -1
			if this.queryParams.format is 'text'
				content = HTTP.call('GET',url).content
			else if this.queryParams.format is 'pdf' or url.toLowerCase().indexOf('.pdf') isnt -1
				content = API.tdm.fulltext(url).fulltext
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

API.add 'tdm/miner', 
	get: () -> return API.tdm.miner this.queryParams.content ? this.queryParams.url, this.queryParams
	post: () -> return API.tdm.miner this.bodyParams.content ? this.bodyParams.url ? this.queryParams.url, this.bodyParams

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
		params.spaces ?= this.queryParams.spaces
		return API.tdm.extract params

API.add 'tdm/emails',
	get: () ->
		return API.tdm.emails this.queryParams


API.tdm._bad_chars = [
	{bad: '‘', good: "'"},
	{bad: '’', good: "'"},
	{bad: '´', good: "'"},
	{bad: '“', good: '"'},
	{bad: '”', good: '"'},
	{bad: '–', good: '-'},
	{bad: '-', good: '-'}
]
API.tdm.clean = (text) ->
	# get rid of MS formatting, stuff like that
	_cln = (t) ->
		nt = false
		if typeof t isnt 'string'
			nt = true
			t = JSON.stringify t
		for c in API.tdm._bad_chars
			re = new RegExp(c.bad,"g")
			t = t.replace(re,c.good)
		return if nt then JSON.parse(t) else t
	if typeof text is 'object'
		for k of text
			try text[k] = _cln text[k]
		return text
	else
		try
			return _cln text
		catch
			return text

API.tdm.stringify = (obj, include=[], ignore=[]) ->
  if typeof obj is 'string'
    s = obj
  else if typeof obj is 'number'
    s = obj.toString()
  else if typeof obj is 'object'
    if Array.isArray obj
      s = JSON.stringify obj
    else
      s = '{'
      for a in _.keys(obj).sort()
        if (not include.length or a in include) and a not in ignore
          s += ',' if s isnt '{'
          s += '"' + a + '":"' + JSON.stringify(obj[a]) + '"'
      s += '}'
  else
    try
      s = JSON.stringify obj
    catch
      s = ''
  return s

API.tdm.diff = (a, b, opts={}) ->
	# can be Chars for comparison char by char. Or Words to compare words ignoring whitespace. Or WordsWithSpace to care about whitespace
	# Or Lines to compare lines. Or Sentences for sentences. Or Patch will do structuredPatch (there are other action options but just use these)
	# may need some pre-processing to handle html without being too fragile to changes humans cannot see
	# or just strip all the content out of the html, unless passed a var saying that it matter?
	# but then how to match back to the correct object? just by content map?
	# https://github.com/kpdecker/jsdiff
	if typeof a is 'string' and a.startsWith('http')
		a = if opts.puppeteer then API.http.puppeteer(a) else HTTP.call('GET', a).content
	if typeof b is 'string' and b.startsWith('http')
		b = if opts.puppeteer then API.http.puppeteer(b) else HTTP.call('GET', b).content
	delete opts.puppeteer
	action = opts.action ? 'Words'
	action = if action.toLowerCase() is 'wordswithspace' then 'WordsWithSpace' else action.substring(0,1).toUpperCase() + action.substring(1).toLowerCase()
	delete opts.action
	#if action in ['Chars','Words']
	#	opts.ignoreCase ?= true
	if action is 'Lines'
		opts.newlineIsToken ?= true
		opts.ignoreWhitespace ?= true
	else
		a = a.replace(/\\n/g,' ').replace(/\s{2,}/g,' ')
		b = b.replace(/\\n/g,' ').replace(/\s{2,}/g,' ')
	if typeof a is 'string' and (a.indexOf('{') is 0 or a.indexOf('[') is 0) and (a.endsWith('}') or a.endsWith(']'))
		try a = JSON.parse a
	if typeof b is 'string' and (b.indexOf('{') is 0 or b.indexOf('[') is 0) and (b.endsWith('}') or b.endsWith(']'))
		try b = JSON.parse b
	if typeof a is 'object' and typeof b isnt 'object'
		a = JSON.stringify a
	if typeof b is 'object' and typeof a isnt 'object'
		b = JSON.stringify b
	if typeof a is 'object' and typeof b is 'object'
		if _.isArray(a) and _.isArray(b)
			# what does this do with arrays of objects? better just to stick with diffJson? or recurse?
			return diff.diffArrays a, b
		else
			# if as above passed arrays to this, does it handle them? or only objects
			return diff.diffJson a, b
	else if action is 'Chars'
		return diff.diffChars a, b, opts
	else if action is 'Words'
		return diff.diffWords a, b, opts
	else if action is 'WordsWithSpace'
		return diff.diffWordsWithSpace a, b, opts
	else if action is 'Lines'
		return diff.diffLines a, b, opts
	else if action is 'Sentences'
		return diff.diffSentences a, b, opts
	else if action is 'Patch'
		return diff.structuredPatch 'a', 'b', a, b
	
# https://www.npmjs.com/package/languagedetect
API.tdm.language = (content) ->
	try content = content.replace(/[.,\/#!$%\^&\*;:{}=\-_`~()0123456789]/g," ")
	try content = content.replace(/\s{2,}/g," ")
	try
		lnd = new languagedetect()
		res = lnd.detect content, 1
		return res[0][0]
	catch
		return ''

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

API.tdm.levenshtein = (a, b, lowercase=true) ->
	if lowercase
		a = a.toLowerCase()
		b = b.toLowerCase()
	minimator = (x, y, z) ->
		return x if x <= y and x <= z
		return y if y <= x and y <= z
		return z

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
		r[0][c] = c
		c++

	i = 1
	while i < m + 1
		r[i] = [i]
		j = 1
		while j < n + 1
			cost = if a.charAt( i - 1 ) is b.charAt( j - 1 ) then 0 else 1
			r[i][j] = minimator( r[i-1][j] + 1, r[i][j-1] + 1, r[i-1][j-1] + cost )
			j++
		i++

	dist = r[ r.length - 1 ][ r[ r.length - 1 ].length - 1 ]
	return distance:dist, length: {a:m, b:n}, detail:r

# https://en.wikipedia.org/wiki/Hamming_distance#Algorithm_example
# this is faster than levenshtein but not always so useful
# this works slightly better with perceptual hashes, or anything where just need to know how many changes to make to become the same
# for example the levenshtein difference between 1234567890 and 0123456789 is 2
# whereas the hamming distance is 10
API.tdm.hamming = (a, b) ->
	if a.length < b.length
		short = a
		long = b
	else
		short = b
		long = a
	pos = long.indexOf short
	short = API.convert.buffer2binary(short) if Buffer.isBuffer short
	long = API.convert.buffer2binary(long) if Buffer.isBuffer long
	ss = short.split('')
	sl = long.split('')
	if sl.length > ss.length
		diff = sl.length - ss.length
		if 0 < pos
			pc = 0
			while pc < pos
				ss.unshift ''
				pc++
				diff--
		c = 0
		while c < diff
			ss.push ''
			c++
	moves = 0
	for k of sl
		moves++ if ss[k] isnt sl[k]
	return moves
	
API.tdm.categorise = (entity) ->
	exists = API.http.cache entity, 'tdm_categorise'
	return exists if exists

	rec = API.use.wikipedia.lookup {title:entity}
	return rec if rec.status is 'error'
	tidy = rec.data.revisions[0]['*'].toLowerCase().replace(/http.*?\.com\//g,'').replace(/\|accessdate.*?<\/ref>/g,'').replace(/<ref.*?\|url/g,'').replace(/access\-date.*?<\/ref>/g,'').replace(/file.*?]]/g,'')
	stops = API.tdm.stopwords()
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
			imghash = crypto.createHash('md5').update(img, 'utf8').digest('hex')
			img = 'https://upload.wikimedia.org/wikipedia/commons/' + imghash.charAt(0) + '/' + imghash.charAt(0) + imghash.charAt(1) + '/' + img
		wikibase = rec.data.pageprops.wikibase_item
		wikidata = if wikibase then 'https://www.wikidata.org/wiki/' + wikibase else undefined
	res = {url:url,img:img,title:rec.data.title,wikibase:wikibase,wikidata:wikidata,keywords:keywords}

	API.http.cache entity, 'tdm_categorise', res
	return res

API.tdm.stopwords = (stops,more,wp=true,gramstops=true) -> 
	stops ?= ['purl','w3','http','https','ref','html','www','ref','cite','url','title','date','nbsp','doi','fig','figure','supplemental',
		'year','time','january','february','march','april','may','june','july','august','september','october','november','december',
		'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec','keywords','revised','accepted','file','attribution',
		'org','com','id','wp','main','website','blogs','media','people','years','made','location','its','asterisk','called','xp','er'
		'image','jpeg','jpg','png','php','object','false','true','article','chapter','book','caps','isbn','scale','axis','accessed','email','e-mail',
		'story','first1','first2','last1','last2','general','list','accessdate','view_news','d0','dq','sfnref','onepage','sfn','authorlink']
	gramstops = ["apos", "as", "able", "about", "above", "according", "accordingly", "across", "actually", "after", "afterwards", 
		"again", "against", "aint", "all", "allow", "allows", "almost", "alone", "along", "already", "also", "although", "always", "am", 
		"among", "amongst", "an", "and", "another", "any", "anybody", "anyhow", "anyone", "anything", "anyway", "anyways", "anywhere", 
		"apart", "appear", "appreciate", "appropriate", "are", "arent", "around", "as", "aside", "ask", "asking", "associated", "at", 
		"available", "away", "awfully", "be", "became", "because", "become", "becomes", "becoming", "been", "before", "beforehand", 
		"behind", "being", "believe", "below", "beside", "besides", "best", "better", "between", "beyond", "both", "brief", "but", "by", 
		"cmon", "cs", "came", "can", "cant", "cannot", "cant", "cause", "causes", "certain", "certainly", "changes", "clearly", "co", 
		"com", "come", "comes", "concerning", "consequently", "consider", "considering", "contain", "containing", "contains", "corresponding", 
		"could", "couldnt", "course", "currently", "definitely", "described", "despite", "did", "didnt", "different", "do", "does", "doesnt", 
		"doing", "dont", "done", "down", "downwards", "during", "each", "edu", "eg", "eight", "either", "else", "elsewhere", "enough", "entirely", 
		"especially", "et", "etc", "even", "ever", "every", "everybody", "everyone", "everything", "everywhere", "ex", "exactly", "example", "except", 
		"far", "few", "fifth", "first", "five", "followed", "following", "follows", "for", "former", "formerly", "forth", "four", "from", "further", 
		"furthermore", "get", "gets", "getting", "given", "gives", "go", "goes", "going", "gone", "got", "gotten", "greetings", "had", "hadnt", 
		"happens", "hardly", "has", "hasnt", "have", "havent", "having", "he", "hes", "hello", "help", "hence", "her", "here", "heres", "hereafter", 
		"hereby", "herein", "hereupon", "hers", "herself", "hi", "him", "himself", "his", "hither", "hopefully", "how", "howbeit", "however", "i", "I", 
		"id", "ill", "im", "ive", "ie", "if", "ignored", "immediate", "in", "inasmuch", "inc", "indeed", "indicate", "indicated", "indicates", "
		inner", "insofar", "instead", "into", "inward", "is", "isnt", "it", "itd", "itll", "its", "itself", "just", "keep", "keeps", "kept", 
		"know", "knows", "known", "last", "lately", "later", "latter", "latterly", "least", "less", "lest", "let", "lets", "like", "liked", "likely", 
		"little", "look", "looking", "looks", "ltd", "mainly", "many", "may", "maybe", "me", "mean", "meanwhile", "merely", "might", "more", "moreover", 
		"most", "mostly", "much", "must", "my", "myself", "name", "namely", "nd", "near", "nearly", "necessary", "need", "needs", "neither", "never", 
		"nevertheless", "new", "next", "nine", "no", "nobody", "non", "none", "noone", "nor", "normally", "not", "nothing", "now", "nowhere", 
		"obviously", "of", "off", "often", "oh", "ok", "okay", "old", "on", "once", "one", "ones", "only", "onto", "or", "other", "others", "otherwise", 
		"ought", "our", "ours", "ourselves", "out", "outside", "over", "overall", "own", "particular", "particularly", "per", "perhaps", "placed", 
		"please", "plus", "possible", "presumably", "probably", "provides", "que", "quite", "qv", "rather", "rd", "re", "really", "reasonably", 
		"regarding", "regardless", "regards", "relatively", "respectively", "right", "said", "same", "saw", "say", "saying", "says", "second", 
		"secondly", "see", "seeing", "seem", "seemed", "seeming", "seems", "seen", "self", "selves", "sensible", "sent", "serious", "seriously", 
		"seven", "several", "shall", "she", "should", "shouldnt", "since", "six", "so", "some", "somebody", "somehow", "someone", "something", 
		"sometime", "sometimes", "somewhat", "somewhere", "soon", "sorry", "specified", "specify", "specifying", "still", "sub", "such", "sup", "sure", 
		"ts", "take", "taken", "tell", "tends", "th", "than", "thank", "thanks", "thanx", "that", "thats", "thats", "the", "their", "theirs", "them", 
		"themselves", "then", "thence", "there", "theres", "thereafter", "thereby", "therefore", "therein", "theres", "thereupon", "these", "they", 
		"theyd", "theyll", "theyre", "theyve", "think", "third", "this", "thorough", "thoroughly", "those", "though", "three", "through", 
		"throughout", "thru", "thus", "to", "together", "too", "took", "toward", "towards", "tried", "tries", "truly", "try", "trying", "twice", 
		"two", "un", "under", "unfortunately", "unless", "unlikely", "until", "unto", "up", "upon", "us", "use", "used", "useful", "uses", "using", 
		"usually", "value", "various", "very", "via", "viz", "vs", "want", "wants", "was", "wasnt", "way", "we", "wed", "well", "weve", 
		"welcome", "well", "went", "were", "werent", "what", "whats", "whatever", "when", "whence", "whenever", "where", "wheres", "whereafter", 
		"whereas", "whereby", "wherein", "whereupon", "wherever", "whether", "which", "while", "whither", "who", "whos", "whoever", "whole", "whom", 
		"whose", "why", "will", "willing", "wish", "with", "within", "without", "wont", "wonder", "would", "would", "wouldnt", "yes", "yet", "you", 
		"youd", "youll", "youre", "youve", "your", "yours", "yourself", "yourselves", "zero"]
	if gramstops
		stops = _.union stops, gramstops
	if more
		stops = _.union stops, more
	if wp
		stops = _.union stops, wordpos.stopwords
	return stops

API.tdm.isnumber = (term) ->
	if typeof term is 'number' or typeof term is 'string' and term.length is term.replace(/[^0-9\~\,\.\-% ]/g,'').length
		return true
	else
		return false
API.tdm.hasnumber = (term) ->
	if typeof term is 'string' and term.length isnt term.replace(/[0-9]/g,'').length
		return true
	else
		return false
		
API.tdm.word = (word,tp='',shortnames=false) ->
	return [] if typeof word isnt 'string' or not word.length
	tp = tp.substring(0,1).toUpperCase() + tp.substring(1).toLowerCase() if tp isnt ''
	_word = Async.wrap (word,callback) ->
		wp = new wordpos()
		wp['lookup' + tp](word, (res) -> 
			if shortnames # e.g. don't want fl to be considered a word just because it means FL for Florida
				return callback null, res
			else if res.length and res[0].lemma isnt word and (not res[0].synonyms? or word.toUpperCase() in res[0].synonyms)
				return callback null, []
			else
				return callback null, res
		)
	return _word word
API.tdm._checkedwords = {} # keep record in running memory of words already checked
API.tdm.isword = (word,tp,shortnames) ->
	return false if API.tdm.isnumber word
	if not tp? and not shortnames?
		return word if word.toLowerCase() in API.tdm.stopwords()
		return API.tdm._checkedwords[word] if API.tdm._checkedwords[word]?
	original = word
	hasing = word.endsWith 'ing'
	word = word.replace(/ing$/,'e') if hasing
	tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and hasing
		word = word.replace(/e$/,'')
		tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and (word.endsWith('ies') or word.endsWith('ied'))
		word = word.replace(/ies$/,'y').replace(/ied$/,'y')
		tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and word.endsWith('es')
		word = word.replace(/es$/,'')
		tw = API.tdm.word word,tp,shortnames
		if _.isEmpty(tw)
			word += 'e'
			tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and word.endsWith('s')
		word = word.replace(/s$/,'')
		tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and word.endsWith('ly')
		word = word.replace(/ly$/,'')
		tw = API.tdm.word word,tp,shortnames
	tryagain = false
	if _.isEmpty(tw) and word.endsWith('ed')
		word = word.replace(/ed$/,'')
		tw = API.tdm.word word,tp,shortnames
		if _.isEmpty tw
			for pair in ['bb','dd','ff','gg','ll','mm','nn','pp','rr','tt','vv','zz']
				if word.endsWith pair
					tryagain = true
					word = word.slice 0, -1
					break
		tw = API.tdm.word(word,tp,shortnames) if tryagain
		if _.isEmpty(tw)
			word += 'e'
			tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and word.endsWith('d') and not tryagain
		word = word.replace(/d$/,'')
		tw = API.tdm.word word,tp,shortnames
	if _.isEmpty(tw) and word.endsWith('n') and not tryagain
		word = word.replace(/n$/,'')
		tw = API.tdm.word word,tp,shortnames
	res = if not _.isEmpty(tw) then word else false
	API.tdm._checkedwords[original] = res
	API.tdm._checkedwords[word] = res if word isnt original
	return res

_lookups = {}
API.tdm.type = (word,verbose) ->
	if _lookups[word]? and not verbose
		return _lookups[word]
	else
		wrd = API.tdm.word word
		wrd = API.tdm.word(API.tdm.isword(word)) if not wrd.length
		if wrd.length
			_lookups[word] = wrd[0].lexName
			return if verbose then wrd else wrd[0].lexName
		else
			return false

API.tdm.generic = (word,filters,verbose) ->
	filters ?= ['adv','verb.stative','noun.act','noun.location','noun.time']
	filters = filters.split(',') if typeof filters is 'string'
	tp = API.tdm.type word, verbose
	if tp is false
		return false
	else
		st = if typeof tp is 'string' then tp else tp[0].lexName
		for f in filters
			if st.indexOf(f) is 0
				return tp
		return false

API.tdm.is = (tp,word) ->
	_word = Async.wrap (tp,word,callback) ->
		wp = new wordpos()
		wp['is'+tp.substring(0,1).toUpperCase() + tp.substring(1).toLowerCase()] word, (res) -> return callback null, res
	return if tp and word then _word(tp, word) else false

API.tdm.words = (content,verbose) ->
	_word = Async.wrap (content,callback) ->
		wp = new wordpos()
		wp.getPOS(content, (res) -> 
			if verbose
				return callback null, res
			else
				words = []
				for k of res # k can be nouns verbs adjectives adverbs
					if k isnt 'rest'
						for w in res[k]
							words.push(w) if w not in words
				return callback null, words.sort()
		)
	return _word content

API.tdm.keywords = (content,opts={},defaults=true) ->
	try
		opts.checksum ?= API.job.sign content, opts
		opts.checksum += defaults
	catch
		opts.checksum ?= crypto.createHash('md5').update(content+JSON.stringify(opts), 'utf8').digest('base64')
		opts.checksum += defaults
	opts.len ?= 2
	opts.stopWords ?= []
	if defaults
		opts.stopWords = _.union opts.stopWords, API.tdm.stopwords()
	try opts.cutoff = (opts.cutoff*100000)/100000 if opts.cutoff? and typeof opts.cutoff isnt 'number'
	exists = API.http.cache opts.checksum, 'tdm_keywords'
	return exists if exists
	keywords = gramophone.extract content, opts
	res = []
	if opts
		for i in keywords
			str = if opts.score then i.term else i
			res.push i if (not opts.len or str.length >= opts.len) and (not opts.max or str.length <= opts.max)
	else
		res = keywords
	try API.http.cache(opts.checksum, 'tdm_keywords', res) if res.length
	return res

API.tdm.extract = (opts) ->
	# opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
	if opts.url and not opts.content
		if opts.url.indexOf('.pdf') isnt -1 or opts.url.indexOf('/pdf') isnt -1
			opts.convert ?= 'pdf'
		else
			opts.content = API.http.puppeteer opts.url, true
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
	text = text.replace(/ /g,'') if opts.spaces is false

	res = {length:text.length, matched:0, matches:[], matchers:opts.matchers, text: text}

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

API.tdm.emails = (opts={}) ->
	#opts.match = '/^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/'
	opts.matchers = ['/([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi','/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi']
	emails = []
	checked = []
	ex = API.tdm.extract opts
	for pm in ex.matches
		for pmr in pm.result
			if pmr not in checked
				vl = API.mail.validate pmr, API.settings.service?.openaccessbutton?.mail?.pubkey
				emails.push(pmr) if vl.is_valid
			checked.push pmr
	return emails
	
API.tdm.entities = (q, options={}) ->
	ret = {ners: [], person: [], organisation: [], location: [], other: []}
	try
		checksum = API.job.sign q, options
		exists = API.http.cache checksum, 'tdm_entities_corenlp'
		res = if exists? then exists else API.use.corenlp.entities q, options
		API.http.cache(checksum, 'tdm_entities_corenlp', res) if not exists? and res?.sentences?
		finds = {}
		for s in res.sentences
			for e in s.entitymentions
				if e.text and e.ner and (not finds[e.ner] or e.text.toLowerCase() not in finds[e.ner])
					ret.ners.push(e.ner) if e.ner not in ret.ners
					finds[e.ner] ?= []
					finds[e.ner].push e.text.toLowerCase()
					if e.ner is 'PERSON'
						ret.person.push {value: e.text}
					else if e.ner is 'ORGANIZATION'
						ret.organisation.push {value: e.text}
					else if e.ner in ['CITY','COUNTRY','LOCATION','STATE_OR_PROVINCE'] and e.text.substring(0,1).toUpperCase() is e.text.substring(0,1) # location is a guess, what else might it put out as locations?
						ret.location.push {value: e.text, type: e.ner.toLowerCase()}
					else
						if e.ner not in ['DATE','TIME','NUMBER','ORDINAL','PERCENT','TITLE','SET','URL']
							ret.other.push {value: e.text, type: e.ner.toLowerCase()}
						# other interesting ones seen so far include 
						# cause-of-death, ordinal, number, date, duration, email, misc, set, percent (for both a number with the word or the symbol), title
		ret.res = res if options.full
		return ret
	catch
		return ret



API.tdm.miner = (text,opts={}) ->
	opts.verbose ?= false
	opts.phrases ?= false
	opts.queries ?= false
	opts.entities ?= true
	opts.keys ?= false
	opts.cluster ?= true
	#opts.limit = 1000 # set a limit to restrict how many are returned
	opts.from ?= 0 # split some of the beginning off, mostly useful for testing
	opts.limit ?= 1000 if opts.verbose and opts.queries # with these both on the result set would get very large
	opts.must ?= [] #[{term: {'snaks.key':'mesh'}}]
	opts.must_not ?= [
		{term: {'snaks.qid.exact':'Q13442814'}}, # scholarly article (it is not useful to have these passed back when mining scholarly articles, unless was scraping for refs
		{term: {'snaks.qid.exact':'Q30612'}}, # clinical trial
		{term: {'snaks.qid.exact':'Q482994'}}, # album
		{term: {'snaks.qid.exact':'Q2188189'}}, # musical work
		{term: {'snaks.qid.exact':'Q3305213'}}, # painting
		{term: {'snaks.qid.exact':'Q4167410'}}, # wikimedia disambiguation page
		{term: {'snaks.property.exact':'P161'}}, # cast member (lots of rubbish about films, comics, games etc not of interest
		{term: {'snaks.property.exact':'P434'}}, # MusicBrainz artist ID
		{term: {'snaks.property.exact':'P435'}}, # MusicBrainz work ID
		{term: {'snaks.property.exact':'P436'}}, # MusicBrainz release group ID
		{term: {'snaks.property.exact':'P5842'}}, # Apple Podcasts podcast ID
		{term: {'snaks.property.exact':'P5797'}}, # Twitch channel ID
		{term: {'snaks.property.exact':'P4983'}}, # TMDb TV series ID
		{term: {'snaks.property.exact':'P4073'}}, # Fandom wiki ID
		{term: {'snaks.property.exact':'P3168'}}, # Sporthorse data ID
		{term: {'snaks.property.exact':'P449'}}, # original broadcaster
		{term: {'snaks.property.exact':'P449'}} # original broadcaster
		#{term: {'snaks.property.exact':'P4835'}}, # TheTVDB.com ID
		#{term: {'snaks.property.exact':'P6839'}}, # TV Tropes identifier
	]

	sopts = {fields:['label','sitelinks.enwiki.title'],size:20}
	sopts.must = opts.must if opts.must? and opts.must.length
	sopts.must_not = opts.must_not if opts.must_not? and opts.must_not.length
	fopts = {size: 1}
	fopts.must = opts.must if opts.must? and opts.must.length
	fopts.must_not = opts.must_not if opts.must_not? and opts.must_not.length

	if text.indexOf('http') is 0 and text.indexOf(' ') is -1
		try text = API.tdm.fulltext(text).fulltext

	extragenerics = ['adv','verb.stative','noun.act','noun.location','noun.time','noun.person','noun.state','verb.possession','adj.all','verb.perception']

	ts = API.tdm.stopwords()
	for a in ['1','2','3','4','5','6','7','8','9','0']
		pos = ts.indexOf a
		ts.splice(pos, 1) if pos isnt -1
	ts = _.union ts, [
		'author','authors','copyright','introduction','conclusion','contact','common','open','commons','direction','areas','vol','ml',
		'asterisk','asterisks','ethics','committee','cite','cited','cites','citation','citations','min','minute','minutes','data',
		'licence','license','licenced','licensed','major'
	]
	counter = 0

	words = text.split ' '
	if opts.from
		words = words.splice opts.from
		text = words.join ' '
	if typeof opts.limit is 'number'
		words = words.splice 0, opts.limit
		text = words.join ' '
	wl = words.length

	clustered = {}
	_crun = (idx, ip, text) ->
		cm = (if ip.indexOf('http') isnt 0 then 'http://' else '') + ip + (if ip.indexOf(':') is -1 then (if API.settings.dev then ':3002' else ':3333') else '') + '/api/tdm/miner'
		copts = _.clone opts
		copts.content = text
		copts.delegated = true
		delete copts.cluster
		clustered[idx] = HTTP.call('POST', cm, {data: copts, timeout: 600000}).data
	_cls =  (idx, ip, text) -> Meteor.setTimeout (() -> _crun idx, ip, text), 1
	if opts.cluster and not opts.delegated and API.settings.cluster?.ip?
		thisip = API.status.ip()
		across = API.settings.cluster.ip.length
		across += 1 if thisip not in API.settings.cluster.ip
		for i of API.settings.cluster.ip
			ip = API.settings.cluster.ip[i]
			if ip isnt thisip
				clustered[i] = false
				_cls i, ip, words.splice(words.length-Math.floor(words.length/across)).join(' ')
				across -= 1
		text = words.join ' '
		wl = words.length

	textl = text.toLowerCase()
	textlc = textl.replace(/[^a-zA-Z0-9 ]/g,'').replace(/  +/g,' ')
	ret = words: wl, searched: 0, skipped: 0, found: 0, entities: 0, terms: [], locations: [], ids: [], phrases: [], entity: [], qrs: [], types: []
	_addwd = (wdr) ->
		snakalysed = if wdr.snakalysed then wdr.snakalysed else API.use.wikidata.snakalyse wdr
		for ms of snakalysed.meta
			wdr[ms] = snakalysed.meta[ms]
		wdr.keys = snakalysed.keys if opts.keys
		delete wdr.snaks
		delete wdr.lastrevid
		delete wdr.sitelinks
		delete wdr.type
		delete wdr.id
		delete wdr.createdAt
		delete wdr.created_date
		delete wdr.updatedAt
		delete wdr.updated_date
		delete wdr.snakalysed
		ret.entity.push wdr
	rtj = ''
	generics = {}
	searched = []
	skipped = []
	phrase = ''
	lastmatch = false
	while counter < wl
		console.log counter
		t = words[counter]
		counter += 1
		if t.length and t.indexOf('http') is -1 and t.indexOf('@') is -1 and not t.startsWith '-'
			td = t.replace(/\//,' ').replace(/[^a-zA-Z0-9\-\.%]/g,'').replace(/\.$/g,'').trim()
			tdl = td.toLowerCase()
			iscaps = if td.toUpperCase() is td then true else false
			isnumber = API.tdm.isnumber td
			hasnumber = API.tdm.hasnumber td
			issw = not hasnumber and tdl in ts
			capstart = if not iscaps and not isnumber and not hasnumber and not issw and td isnt tdl and td.substring(0,1).toUpperCase() is td.substring(0,1) then true else false
			next = if counter < wl then words[counter+1] else ''
			bracketed = if t.indexOf('(') is 0 and t.indexOf(',') is -1 and next not in ts then true else false
			parts = phrase.split ' '
			end = if counter > 2 then words[counter-2] else ''
			start = if end.endsWith(';') or end.endsWith('.') then false else if td.length > 2 and not isnumber and not maybeid and not hasnumber and not issw and td.substring(0,1).toUpperCase() is td.substring(0,1) and end.substring(0,1).toUpperCase() isnt end.substring(0,1) and end isnt 'of' and not end.endsWith(',') and td.toUpperCase() isnt td then true else false
			isgeneric = if td in generics then generics[td] else if issw then true else if not isnumber and not hasnumber and not iscaps then API.tdm.generic(td) else false
			generics[td] = isgeneric if not generics[td]?
			islocation = if (isgeneric is 'noun.location' or tdl is 'shanghai') and not issw and capstart then true else false
			if islocation and td not in ret.locations
				ret.locations.push td
				if td not in searched and opts.entities
					searched.push td
					locwd = API.use.wikidata.find 'sitelinks.enwiki.title.exact': td, true, true, true, fopts
					_addwd(locwd) if locwd?
			maybeid = if td.length > 2 and not isnumber and not islocation and not isgeneric and td.slice(-1) isnt '%' and td.replace(/[^0-9A-Z\.\-%]/g,'').length isnt 0 and td.substring(0,1).toUpperCase() is td.substring(0,1) and td.substring(1,2).toUpperCase() is td.substring(1,2) then true else false
			if maybeid # check it with a query? on snak values?
				if td not in ret.ids and tdl not in searched
					searched.push tdl
					idwd = API.use.wikidata.find 'label.exact': td, true, true, true, fopts
					if idwd # could save all possible IDs even if no match in wikidata... gets lots more junk though. With searches misses some, but is much cleaner
						_addwd(idwd) if opts.entities
						ret.ids.push td
						if td.endsWith('s') and td.replace(/s$/,'').toUpperCase() is td.replace(/s$/,'')
							dupin = ret.ids.indexOf td
							ret.ids.splice(dupin,1) if dupin isnt -1 and dupin isnt ret.ids.length-1
						else if iscaps
							dups = ret.ids.indexOf td + 's'
							ret.ids.splice(dups,1) if dups isnt -1 and dups isnt ret.ids.length-1
		
			pl = phrase.toLowerCase()
			ptl = pl.replace(/[^a-zA-Z0-9 ]/g,'').replace(/  +/g,' ')
			if phrase.length > 2 and not API.tdm.isnumber(phrase) and ptl not in searched and rtj.indexOf(ptl) is -1 and (parts.length isnt 1 or not API.tdm.generic phrase)
				if parts.length > 3 and searched.length and (ptl.indexOf(searched[searched.length-1]) is 0 or (searched.length > 1 and ptl.indexOf(searched[searched.length-2]) is 0) or (searched.length > 2 and ptl.indexOf(searched[searched.length-3]) is 0) or (searched.length > 3 and ptl.indexOf(searched[searched.length-4]) is 0))
					skipped.push(ptl) if opts.verbose
				else
					searched.push ptl
					pcl = phrase.replace(/[^0-9a-zA-Z\-\.\, ]/g,'').replace(/,$/,'').replace(/\.$/,'')
					qr = 'label:"' + pcl + '" OR sitelinks.enwiki.title:"' + pcl + '"'
					wd = API.use.wikidata.search qr, undefined, undefined, undefined, sopts
					ret.qrs.push(wd) if opts.verbose and opts.queries
					for w in wd?.hits?.hits ? []
						wt = if w.fields?['sitelinks.enwiki.title']? and w.fields['sitelinks.enwiki.title'].length and (not w.fields?.label? or not w.fields.label.length or w.fields.label[0].length < w.fields?['sitelinks.enwiki.title'][0].length) then w.fields['sitelinks.enwiki.title'][0] else if w.fields?.label? and w.fields.label.length then w.fields.label[0] else ''
						if pl.indexOf(wt.toLowerCase().split(' ')[0]) isnt -1
							wtl = wt.toLowerCase().replace(/[^a-z0-9 ]/g,'').replace(/  +/g,' ')
							if wt.length and wtl.indexOf(ptl.split(' ')[0].toLowerCase()) is 0 and textlc.indexOf(wtl) isnt -1 and (wt.toUpperCase() isnt wt or text.indexOf(wt) isnt -1) and rtj.indexOf(wtl) is -1
								if ret.terms.length and wtl.indexOf(ret.terms[ret.terms.length-1].toLowerCase()) is 0
									ret.terms.pop()
								else if opts.entities and lastmatch
									lastrec = API.use.wikidata.get lastmatch, true, true, true
									lastmatch = false
									_addwd(lastrec) if lastrec?
								if wt.indexOf(' ') isnt -1 or not API.tdm.generic wt, extragenerics
									ret.terms.push wt
									lastmatch = w._id
									lastlabel = wt
									ret.types.push({val: wt, type: API.tdm.type wt}) if wt.indexOf(' ') is -1 and opts.verbose
									rtj += (if rtj.length then ' ' else '') + wtl
								if phrase.length and wt.split(' ').length isnt parts.length
									counter += wt.split(' ').length-1 if wtl.indexOf(phrase.toLowerCase()) is 0
									phrase = ''
								break # could break here...
				if (opts.phrases or opts.verbose) and phrase.length and parts.length > 1 and (issw or start or bracketed) and rtj.indexOf(ptl) is -1
					pcp = phrase.replace(/\.$/,'').replace(/,$/,'')
					keeper = []
					if pcp not in ret.phrases
						for part in parts
							part = part.replace(/,/g,'')
							if part.length > 2 and part not in ret.ids and part not in ret.locations and part not in ret.phrases and rtj.indexOf(part) is -1 and not API.tdm.isnumber part
								gen = API.tdm.generic part, extragenerics
								if not gen or text.split(part).length is 2
									keeper.push part
					ret.phrases.push(pcp) if keeper.length
			if issw or start or bracketed
				phrase = ''
			if (phrase.length isnt 0 or not isgeneric) and td.length
				phrase += (if phrase.length then ' ' else '') + td + (if t.endsWith(',') then ',' else '')
				
	ret.searched = searched.length

	if not _.isEmpty clustered
		done = false
		while not done
			alldone = true
			for k of clustered
				alldone = false if clustered[k] is false
			done = alldone
			future = new Future()
			Meteor.setTimeout (() -> future.return()), 500
			future.wait()
		for c in _.keys(clustered).sort().reverse()
			for rk in _.keys ret
				if typeof ret[rk] is 'number' and typeof clustered[c][rk] is 'number'
					ret[rk] += clustered[c][rk]
				else if _.isArray(ret[rk]) and _.isArray clustered[c][rk]
					if rk is 'entity'
						unqs = _.pluck ret[rk], 'label'
						for er in clustered[c][rk]
							if er.label not in unqs
								unqs.push er.label
								ret[rk].push er
					else
						ret[rk] = _.union ret[rk], clustered[c][rk]

	ret.found = ret.terms.length + ret.ids.length + ret.locations.length
	ret.entities = ret.entity.length

	if opts.verbose
		ret.searched = searched
		ret.skipped = skipped
		ret.generics = generics
		ret.text = text
	else
		delete ret.phrases if not opts.phrases
		delete ret.types
		delete ret.skipped
		delete ret.qrs
	return ret



# a pdf that can be got directly: https://www.cdc.gov/mmwr/volumes/69/wr/pdfs/mm6912e3-H.
# pdfjs can get the one above and render it fine. But pdfjs cannot get the one below. A 
# call using request directly with the right settings can get the one below, but is corrupt to pdfjs, even though content is there
# one that needs cookie headers etc: https://journals.sagepub.com/doi/pdf/10.1177/0037549715583150
# so need a way to be able to get with headers etc, and also get an uncorrupted one (corruption by non-xhr methods is a known problem hence why pdfjs uses xhr directly)
API.tdm.fulltext = (url,opts={}) ->
	if url.replace(/\/$/,'') is 'https://www.biorxiv.org/content/biorxiv/early/2020/04/12/2020.04.07.030742.full.pdf'
		return fulltext: '' # a probelm with this particular pdf causes the system to get stuck, have not found a way to avoid it yet, could be to do with lots of images in the file
	
	opts.min ?= 10000 # shortest acceptable fulltext length
	opts.pdf ?= true # prefer PDF fulltext if possible
	opts.refresh ?= false

	checksum = API.job.sign url
	#try
	'''if opts.refresh isnt true and opts.refresh isnt 'true'
		opts.refresh = parseInt(opts.refresh) if typeof opts.refresh is 'string'
		exists = API.http.cache checksum, 'tdm_fulltexts', undefined, refresh
		return exists if exists'''

	# check what is at the given url
	res = {url: url, errors: [], words: 0, fulltext: ''}
	res.resolve = API.http.resolve url
	res.target = res.url #if res.resolve then res.resolve else res.url
	res.head = API.http.get res.target, action: 'head' # would the head request as well? Will need to wait and see
	
	if res.head?.response?.headers?['content-type']? and res.head.response.headers['content-type'].indexOf('/html') isnt -1
		try
			#res.get = API.http.get res.target # need puppeteer, some sites such as epmc serve nothing useful without it
			res.html = API.http.puppeteer res.target #res.get.response.body
			# check for pubmed fulltext link
			if url.indexOf('pubmed') isnt -1 and res.html.indexOf('free_status="free"') isnt -1
				pubf = res.html.split('free_status="free"')[0].replace('href =','href=').replace('= ','=').split('href="')[1].split('"')[0]
				return API.tdm.fulltext pubf

			#delete res.get.response.body
			bi = res.html.toLowerCase().indexOf('<body')
			body = res.html.substring(bi)
			bbi = body.toLowerCase().indexOf('</body')
			body = body.substring(0,bbi)
			body = body.replace(/<script.*?<\/script>/gi,'')
			if opts.title?
				ti = body.toLowerCase().indexOf(opts.title.toLowerCase())
				body = opts.title + ' ' + body.substring(ti) if ti isnt -1
			if body.toLowerCase().indexOf('references') isnt -1
				body = body.replace(/References/g,'references')
				body = body.replace(/\r?\n|\r/g,'')
				rpts = body.split('>references')
				res.references = rpts.pop().replace(/.*?>/,'')
				if res.references.toLowerCase().indexOf('>figures') isnt -1
					res.references = res.references.replace('Figures','figures')
					rfpts = res.references.split('>figures')
					rfpts.pop()
					res.references = rfpts.join('>figures')
				body = rpts.join('>references')
			ai = body.toLowerCase().indexOf('abstract')
			if ai isnt -1
				body = body.substring(ai)
				body = opts.title + ' ' + body if opts.title
			try res.fulltext = API.convert.html2txt(body).replace(/\r?\n|\r/g,' ').replace(/\t/g,' ').replace(/\[.*?\]/g,'')
			# could strip [] links here, and store all the ones that seem to be images

	fll = res.fulltext.toLowerCase()
	if (opts.ispdf or res.target.indexOf('.pdf') isnt -1 or (res.head?.response?.headers?['content-type']? and res.head.response.headers['content-type'].indexOf('/pdf') isnt -1)) and (opts.pdf is true or res.fulltext.length < opts.min or (fll.indexOf('introduction') is -1 and fll.indexOf('conclusion') is -1))
		res.pdf = res.target
		try
			res.sections = []
			res.count = 0
			res.pages = false
			ran = 0
			hold = true
			pages = {}
			headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36'}
			if res.head?.response?.request?.headers?.referer?
				headers.referer = res.head.response.request.headers.referer
			if res.head?.response?.request?.headers?.cookie?
				headers.cookie= res.head.response.request.headers.cookie
			pdfjs.getDocument({url:res.target, maxImageSize:1, disableFontFace: true, withCredentials:true, httpHeaders:headers}).then((pdf) ->
				res.pages = pdf._pdfInfo.numPages
				while res.count < res.pages
					res.count += 1
					page = pdf.getPage res.count
					page.then((page) ->
						page.getTextContent().then((text) ->
							res.sections.push text
							ft = ''
							lastpos = 1000000
							prev = false
							for t in text.items
								t.str = t.str.replace(/"/g,' ').replace(/“/g,' ').replace(/”/g,' ').replace(/’/g,' ').replace(/\r?\n|\r/g,' ').replace(/\t/g,' ')
								if prev isnt false
									t.str = prev + t.str
									prev = false
								trimmed = t.str.trim()
								webormail = (trimmed.indexOf('http') is 0 or trimmed.indexOf('@') isnt -1) and trimmed.indexOf(' ') is -1
								t.str = t.str + ' ' if webormail # make sure URLs get spaced out from surrounding text
								firstword = if t.str.length is 1 then t.str else t.str.split(' ')[0].split('-')[0].replace(/[^a-zA-Z]/g,'')
								lastword = ft.split(' ').pop().replace(/-$/,'').split('-').pop().replace(/[^a-zA-Z]/g,'')
								fwiw = false
								lwiw = false
								flwiw = false
								needspace = ft isnt '' and ft.slice(-1) not in [' ','-']
								if needspace and firstword.substring(0,1).toUpperCase() isnt firstword.substring(0,1) and not webormail and lastword.length and lastword.toUpperCase() isnt lastword
									if flwiw = API.tdm.isword lastword+firstword
										needspace = false
									else if not fwiw = API.tdm.isword firstword
										if t.str.indexOf(' ') is -1
											prev = t.str.replace(/-$/,'')
										else if not lwiw = API.tdm.isword lastword
											needspace = false
								if t.transform? and t.transform[5] < lastpos
									if ft.slice(-1) is '-' and lastword.toUpperCase() isnt lastword and (not fwiw or flwiw or not API.tdm.isword(firstword) or API.tdm.isword(lastword+firstword))
										ft = ft.replace(/-$/,'')
									else if t.str.indexOf('-') is 0
										t.str = t.str.replace('-','')
								if prev is false
									ft += (if needspace then ' ' else '') + t.str
								try lastpos = t.transform[5]
							pages[page.pageIndex] = ft
							ran += 1
						).catch((err) ->
							ran += 1
							res.errors.push err
						)
					).catch((err) -> 
						ran += 1
						res.errors.push err
					)
			).catch((err) ->
				res.errors.push err
				res.pages = 0 if res.pages is false
				hold = false
			)
			while hold is true and (res.pages is false or ran < res.pages)
				future = new Future()
				Meteor.setTimeout (() -> future.return()), 200
				future.wait()
			tp = 0
			while tp < ran
				if typeof pages[tp.toString()] is 'string' and pages[tp.toString()].length
					res.fulltext += ' ' if res.fulltext isnt ''
					res.fulltext += pages[tp.toString()]
				tp += 1
			if res.fulltext.length > opts.min or opts.pdf
				if res.fulltext.length and res.html
					res.htmltext = res.fulltext
				res.fulltext = res.fulltext.replace(/\r?\n|\r/g,' ').replace(/\t/g,' ').replace(/  +/g,' ').trim()
				refloc = res.fulltext.toLowerCase().indexOf('references')
				if refloc isnt -1 and refloc > (res.fulltext.length*.7)
					res.references = res.fulltext.substring(refloc).replace(/references/i,'')
					# safe to try splitting references on figures?
					res.fulltext = res.fulltext.substring(0,refloc)

	fll = res.fulltext.toLowerCase()
	if (res.fulltext.length < opts.min or (fll.indexOf('introduction') is -1 and fll.indexOf('conclusion') is -1)) and not opts.ispdf and res.head?.response?.headers?['content-type']? and res.head.response.headers['content-type'].indexOf('/html') is -1 and res.head.response.headers['content-type'].indexOf('/pdf') is -1
		# could be some other kind of file, try to get it
		try
			ft = API.convert.file2txt res.target, {from: res.head.response.headers['content-type']}
			if typeof ft is 'string' and ft.length > opts.min
				res.htmltext = res.fulltext if res.fulltext.length and res.html and not res.htmltext
				res.pdftext = res.fulltext if res.fulltext.length and res.pdf and res.pages
				res.fulltext = ft.replace(/\r?\n|\r/g,' ').replace(/\t/g,' ')
    
	fll = res.fulltext.toLowerCase()
	if not opts.ispdf and (opts.pdf or res.fulltext.length < opts.min or (fll.indexOf('introduction') is -1 and fll.indexOf('conclusion') is -1)) and res.html and not res.pdf
		htmll = res.html.toLowerCase()
		if htmll.indexOf('pdf') isnt -1
			# look for possible pdf links in the html
			pdflink = ''
			if htmll.indexOf('citation_pdf_url') isnt -1
				pl = htmll.split('citation_pdf_url')[0].split('<').pop()
				pr = htmll.split('citation_pdf_url')[1].split('>')[0]
				wh = if pl.indexOf('content') isnt -1 then pl else pr
				pdflink = wh.replace(/ /g,'').split('content=')[1].replace('"','').replace('"','')
			else if htmll.indexOf('.pdf</a') isnt -1 #the pdf is in the name but may not be on the link, a la https://hal.archives-ouvertes.fr/hal-02510642/document
				pdflink = htmll.split('.pdf</a')[0].split('href').pop().split('"')[1]
			else if htmll.indexOf('.pdf"') isnt -1
				pdflink = htmll.split('.pdf"')[0].split('"').pop() + '.pdf'
			else if htmll.indexOf('pdf') isnt -1
				# look for a link with pdf in it, somewhere near the top of the doc
				htop = htmll.split('<body')[0] + body.substring(0,Math.floor(body.length/4))
				if htop.indexOf('pdf') isnt -1
					tags = htop.split('<')
					for t in tags
						tag = t.split('>')[0]
						if pdflink is '' and tag.indexOf('pdf') isnt -1
							tt = if tag.indexOf("'") isnt -1 then "'" else '"'
							tss = tag.split(tt)
							for tg in tss
								if tg.indexOf('pdf') isnt -1 and (tg.indexOf('http') isnt -1 or tg.indexOf('/') isnt -1)
									pdflink = tg.trim()
									break
			if pdflink.indexOf('"') isnt -1 or pdflink.indexOf("'") isnt -1
				qt = if pdflink.indexOf("'") isnt -1 then "'" else '"'
				pts = pdflink.split(qt)
				for pt in pts
					if pt.indexOf('http') isnt -1 or pt.indexOf('/') isnt -1
						pdflink = pt.trim()
						break
			if pdflink isnt '' and pdflink.indexOf('http') isnt 0
				rtp = res.target.split('://')[1].split('?')[0].split('#')[0].replace(/\/$/, '')
				pdflink = res.target.split('://')[0] + '://' + (if pdflink.indexOf('/') is 0 then rtp.split('/')[0] else rtp + '/') + pdflink
			if typeof pdflink is 'string' and pdflink.indexOf('http') is 0
				try
					res.pdf = pdflink
					rs = API.tdm.fulltext pdflink, {ispdf:true}
					if rs.fulltext
						res.htmltext = res.fulltext if res.fulltext.length and not res.htmltext
						res.fulltext = rs.fulltext
						for k of rs
							res[k] ?= rs[k]

	# sometimes we get a static page not served as html but actually is - convert that to text once more, just in case
	if res.fulltext.toLowerCase().indexOf('<html') is 0
		try res.fulltext = API.convert.html2txt(res.fulltext).replace(/\r?\n|\r/g,' ').replace(/\t/g,' ').replace(/\[.*?\]/g,'')

	#if res.fulltext.length
	#	chc = fulltext: res.fulltext, url: res.url, pdf: res.pdf, references: res.references
	#	API.http.cache(checksum, 'tdm_fulltexts', chc)
	return res

