
# at 17/01/2016 dissemin searches crossref, base, sherpa/romeo, zotero primarily,
# and arxiv, hal, pmc, openaire, doaj, perse, cairn.info, numdam secondarily via oa-pmh
# see http://dissem.in/sources
# http://dev.dissem.in/api.html

API.use ?= {}
API.use.dissemin = {}

API.add 'use/dissemin/doi/:doipre/:doipost',
  get: () -> return API.use.dissemin.doi this.urlParams.doipre + '/' + this.urlParams.doipost


API.use.dissemin.doi = (doi) ->
  url = 'http://beta.dissem.in/api/' + doi
  API.log 'Using dissemin for ' + url
  res = API.cache.get doi, 'dissemin_doi'
  if not res?
    try
      res = HTTP.call 'GET', url
      res = if res.data?.paper? then res.data.paper else undefined
      if res?
        op = API.use.dissemin.open res, true
        res.open = op.open
        res.blacklist = op.blacklist
        API.cache.save doi, 'dissemin_doi', res
      return res
    catch
      return undefined
  else
    return res
    
API.use.dissemin.open = (record,blacklist) ->
  # Dissemin will return records that are to "open" repos, but without a pdf url
  # they could just be repos with biblio records. For now these are not included
  # So we just blacklist researchgate URLs
	res = {open: record.pdf_url}
	if res.open?
	  try
      resolves = HTTP.call 'HEAD', res.open
    catch
      res.open = undefined
	res.blacklist = res.open.toLowerCase().indexOf('researchgate') isnt -1 if res.open and blacklist
	return if blacklist then res else (if res.open then res.open else false)

