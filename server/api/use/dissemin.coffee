
# at 17/01/2016 dissemin searches crossref, base, sherpa/romeo, zotero primarily,
# and arxiv, hal, pmc, openaire, doaj, perse, cairn.info, numdam secondarily via oa-pmh
# see http://dissem.in/sources
# http://dev.dissem.in/api.html

API.use ?= {}
API.use.dissemin = {}

API.add 'use/dissemin/doi/:doipre/:doipost',
  get: () -> return API.use.dissemin.doi this.urlParams.doipre + '/' + this.urlParams.doipost

API.add 'use/dissemin/search/:qry',
  get: () -> return API.use.dissemin.search this.urlParams.qry, this.queryParams.from, this.queryParams.size

API.use.dissemin.doi = (doi) ->
  url = 'http://beta.dissem.in/api/' + doi
  API.log 'Using dissemin for ' + url
  try
    res = HTTP.call 'GET', url
    return if res.data.paper then { data: res.data.paper} else { data: res.data}
  catch err
    return if err.toString().indexOf('404') isnt 0 then 404 else { status: 'error', data: err}

