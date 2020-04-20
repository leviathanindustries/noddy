
import gramophone from 'gramophone'
import CryptoJS from 'crypto-js' # TODO no need for this when crypto is available, fix below then remove
import crypto from 'crypto'
import natural from 'natural'
import wordpos from 'wordpos'
import stopword from 'stopword'
import languagedetect from 'languagedetect'
import Future from 'fibers/future'
import pdfjs from 'pdfjs-dist'

# TODO check out nodenatural and add it in here where useful
# https://github.com/NaturalNode/natural#tf-idf
# ALSO use the stopword package to strip stopwords from any text that needs processing
# https://www.npmjs.com/package/stopword
# and have a look at wordpos too
# https://github.com/moos/wordpos

API.tdm = {}

API.add 'tdm/fulltext', 
  get: () -> 
    res = API.tdm.fulltext this.queryParams.url
    return if this.queryParams.verbose then res else res.fulltext

API.add 'tdm/levenshtein',
	get: () ->
		if this.queryParams.a and this.queryParams.b
			return API.tdm.levenshtein this.queryParams.a, this.queryParams.b
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

API.add 'tdm/miner', get: () -> return API.tdm.miner this.queryParams.content ? this.queryParams.url, this.queryParams

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

API.tdm.levenshtein = (a,b) ->
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
	return distance:dist,detail:r

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
			imghash = CryptoJS.MD5(img).toString() # TODO use crypto instead of crypto-js here
			img = 'https://upload.wikimedia.org/wikipedia/commons/' + imghash.charAt(0) + '/' + imghash.charAt(0) + imghash.charAt(1) + '/' + img
		wikibase = rec.data.pageprops.wikibase_item
		wikidata = if wikibase then 'https://www.wikidata.org/wiki/' + wikibase else undefined
	res = {url:url,img:img,title:rec.data.title,wikibase:wikibase,wikidata:wikidata,keywords:keywords}

	API.http.cache entity, 'tdm_categorise', res
	return res

API.tdm.stopwords = (stops,more,wp=true,gramstops=true) -> 
	stops ?= ['purl','w3','http','https','ref','html','www','ref','cite','url','title','date','state','nbsp','doi','fig','figure',
		'year','time','january','february','march','april','may','june','july','august','september','october','november','december',
		'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec',
		'org','com','id','wp','main','website','blogs','media','people','years','made','location','its','asterisk','called','xp','er'
		'image','jpeg','jpg','png','php','object','false','true','article','chapter','book','caps','isbn','scale','axis','accessed'
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
	if typeof term is 'number' or typeof term is 'string' and term.length is term.replace(/[^0-9\.\-% ]/g,'').length
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
	if _.isEmpty(tw) and word.endsWith('ies')
		word = word.replace(/ies$/,'y')
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

API.tdm.entities = (q, options={}) ->
	ret = {ners: [], person: [], organisation: [], location: [], other: []}
	try
		res = API.use.corenlp.entities q, options
		finds = {}
		for s in res.sentences
			for e in s.entitymentions
				if e.text and e.ner and (not finds[e.ner] or e.text.toLowerCase() not in finds[e.ner])
					ret.ners.push e.ner
					finds[e.ner] ?= []
					finds[e.ner].push e.text.toLowerCase()
					if e.ner is 'PERSON'
						ret.person.push {value: e.text}
					else if e.ner is 'ORGANIZATION'
						ret.organisation.push {value: e.text}
					else if e.ner in ['CITY','COUNTRY','LOCATION'] # location is a guess, what else might it put out as locations?
						ret.location.push {value: e.text, type: e.ner.toLowerCase()}
					else
						ret.other.push {value: e.text, type: e.ner.toLowerCase()}
						# other interesting ones seen so far include 
						# cause-of-death, ordinal, number, date, duration, email, misc, set, percent (for both a number with the word or the symbol), title
		ret.res = res if options.full
		return ret
	catch
		return ret



API.tdm.miner = (text, opts={}) ->
	if text.indexOf('http') is 0 and text.indexOf(' ') is -1
		try text = API.tdm.fulltext(text).fulltext
	opts.splits ?= {}
	opts.splits.abstract ?= true
	opts.splits.intro ?= true
	opts.splits.conclusion ?= true

	if opts.splits.abstract and text.indexOf('Abstract') isnt -1
		parts = text.split('Abstract')
		text = parts[1] if parts.length is 2
	if opts.splits.intro and text.indexOf('Introduction') isnt -1
		parts = text.split('Introduction')
		text = parts[1] if parts.length is 2
	if opts.splits.conclusion and text.indexOf('Conclusion') isnt -1
		pts = text.split('Conclusion')
		if pts.length is 2
			pts[1] = pts[1].split('Appendix')[0].split('Abbreviations')[0].split('Contributions')[0].split('Supplementary')[0].split('Figures')[0].split('Acknowledgements')[0].split('Ethics approval')[0].split('Funding')[0]
			text = pts[0] + 'Conclusion' + pts[1]
			
	ret = count: 0, phrases: [''], ids: [], locations: []
	ts = API.tdm.stopwords()
	for a in ['1','2','3','4','5','6','7','8','9','0']
		pos = ts.indexOf a
		if pos isnt -1
			ts.splice pos, 1
	ts = _.union ts, ['author','authors','copyright','introduction','conclusion','contact','common','open','commons','direction','areas','vol','ml']
	counter = 0

	words = text.split ' '
	wl = words.length-1
	for tc of words
		t = words[tc]
		if t.length and t.indexOf('http') is -1 and t.indexOf('@') is -1
			td = t.replace(/\//,' ').replace(/[^a-zA-Z0-9\-\.%]/g,'').replace(/\. /g,' ').replace(/\.$/g,'').trim()
			tdl = td.toLowerCase()
			iscaps = if td.toUpperCase() is td then true else false
			isnumber = API.tdm.isnumber td
			hasnumber = API.tdm.hasnumber td
			issw = not hasnumber and tdl in ts
			if isnumber or hasnumber or iscaps
				wrd = []
			else
				wrd = API.tdm.word td
				wrd = API.tdm.word(API.tdm.isword(td)) if not wrd.length
			tp = if wrd.length then wrd[0].lexName else ''
			isadv = if tp.startsWith('adv') then true else false
			islocation = if (tp is 'noun.location' or tdl is 'shanghai') and not issw then true else false
			ret.locations.push(td) if islocation and td not in ret.locations
			maybeid = if td.length > 2 and not isnumber and not islocation and not issw and td.slice(-1) isnt '%' and td.replace(/[^0-9A-Z\.\-%]/g,'').length isnt 0 and td.substring(0,1).toUpperCase() is td.substring(0,1) and td.substring(1,2).toUpperCase() is td.substring(1,2) then true else false
			if maybeid
				ret.ids.push(td) if td not in ret.ids
				if td.endsWith('s') and td.replace(/s$/,'').toUpperCase() is td.replace(/s$/,'')
					dupin = ret.ids.indexOf td
					ret.ids.splice(dupin,1) if dupin isnt -1 and dupin isnt ret.ids.length-1
				else if iscaps
					dups = ret.ids.indexOf td + 's'
					ret.ids.splice(dups,1) if dups isnt -1 and dups isnt ret.ids.length-1
			next = if tc < wl then words[tc+1] else ''
			bracketed = if t.indexOf('(') is 0 and t.indexOf(',') is -1 and next not in ts then true else false
			end = ret.phrases[counter].split(' ').pop()
			start = if td.length > 2 and not isnumber and not maybeid and not hasnumber and not issw and td.substring(0,1).toUpperCase() is td.substring(0,1) and end.substring(0,1).toUpperCase() isnt end.substring(0,1) and end isnt 'of' and not end.endsWith(',') and td.toUpperCase() isnt td then true else false
			if ret.phrases[counter].length and (bracketed or start)
				ret.phrases.push ''
				counter += 1
			if td.length and (hasnumber or (not issw and not isadv)) or (((isadv and td isnt 'in') or (td in ['is','thus','a','the','around','are','might','be']) and ret.phrases[counter].split(' ').length > 2) or td is 'of' and ret.phrases[counter].length)
				ret.phrases[counter] += (if ret.phrases[counter].length then ' ' else '') + td + (if t.endsWith(',') then ',' else '')
			if ret.phrases[counter].length and (t.endsWith('.') or (issw and td not in ['of','as','is','around','might','be','a'] and (td not in ['or','and'] or not end.endsWith(','))))
				ret.phrases.push ''
				counter += 1
        
			if counter > 2 and last = ret.phrases[counter-1]
				if last.endsWith(',')
					ret.phrases[counter-1] = ret.phrases[counter-1].replace(/,$/,'')
					last = last.replace(/,$/,'')
				lasts = last.split ' '
				ll = lasts[lasts.length-1]
				if ll in ts or lasts.length < 4 or (last.indexOf(',') isnt -1 and lasts.length > 20) or (last.indexOf(',') is -1 and lasts.length > 9)
					keep = []
					if lasts.length < 4
						for l in lasts
							l = l.replace(',','')
							if l not in ret.ids and l not in ret.locations and l not in ret.phrases and not API.tdm.isnumber l
								llw = API.tdm.word l
								llw = API.tdm.word(API.tdm.isword(l)) if not llw.length
								llt = if llw.length then llw[0].lexName else ''
								if llt in ['noun.substance','noun.artifact'] or llt is '' and text.split(l).length is 2
									keep.push l
					kj = keep.join ' '
					#li = ret.phrases.indexOf last 
					if not keep.length #or (li isnt -1 and li < ret.phrases.length-2)
						ret.phrases[counter-1] = ''
						ret.phrases.pop()
						counter -= 1
					else
						ret.phrases[counter-1] = kj

			'''if counter > 2 and lst = ret.phrases[counter-1]
				lpi = ret.phrases.indexOf lst
				if lpi isnt -1 and lpi < ret.phrases.length-2
					ret.phrases.pop()
					counter -= 1'''

			rpl = ret.phrases.length-1
			if counter > 2 and ret.phrases[rpl] is ''
				if API.tdm.is('adverb', ret.phrases[rpl-1].split(' ').pop()) #or API.tdm.is('adverb', ret.phrases[rpl-1].split(' ')[0].replace(',',''))
					ret.phrases.splice rpl-1, 1
					counter -= 1
				else
					for p of ret.phrases
						if parseInt(p) < rpl-1 and ret.phrases[rpl-1].indexOf(ret.phrases[p]) isnt -1
							ret.phrases.splice rpl-1, 1
							counter -= 1
							break

	ret.count = counter
	return ret



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
	opts.refresh ?= 0

	checksum = API.job.sign url
	try
		if opts.refresh isnt true and opts.refresh isnt 'true'
			opts.refresh = parseInt(opts.refresh) if typeof opts.refresh is 'string'
			if typeof opts.refresh is 'number'
				exists = API.http.cache checksum, 'tdm_fulltexts', undefined, refresh
				return exists if exists

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

	try API.http.cache(checksum, 'tdm_fulltexts', res) if res.fulltext.length
	return res

