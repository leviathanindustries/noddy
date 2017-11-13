
# docs http://www.sherpa.ac.uk/romeo/apimanual.php?la=en&fIDnum=|&mode=simple
# has an api key set in settings and should be appended as query param "ak"

# A romeo query for an issn is what is immediately required: 
# http://www.sherpa.ac.uk/romeo/api29.php?issn=1444-1586

# returns an object in which <romeoapi version="2.9.9"><journals><journal> confirms the journal
# and <romeoapi version="2.9.9"><publishers><publisher><romeocolour> gives the romeo colour
# (interestingly Elsevier is green...)

API.use ?= {}
API.use.sherpa = {romeo:{}}

API.add 'use/sherpa/romeo/search', get: () -> return API.use.sherpa.romeo.search this.queryParams

API.add 'use/sherpa/romeo/colour/:issn', get: () -> return API.use.sherpa.romeo.colour this.urlParams.issn


API.use.sherpa.romeo.search = (params) ->
	apikey = API.settings.use?.romeo?.apikey
	return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
	url = 'http://www.sherpa.ac.uk/romeo/api29.php?ak=' + apikey + '&'
	url += q + '=' + params[q] + '&' for q of params
	res = HTTP.call 'GET', url
	result = API.convert.xml2json undefined,res.content
	return if res.statusCode is 200 then { data: {journals: result.romeoapi.journals, publishers: result.romeoapi.publishers}} else { status: 'error', data: result}

API.use.sherpa.romeo.colour = (issn) ->
	resp = API.use.sherpa.romeo.search {issn:issn}
	try
		return { data: resp.data.publishers[0].publisher[0].romeocolour[0]}
	catch err
		return { status: 'error', data: resp, error: err}

