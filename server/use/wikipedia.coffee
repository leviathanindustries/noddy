

API.use ?= {}
API.use.wikipedia = {}
API.use.wikidata = {}
API.use.wikinews = {}

API.add 'use/wikipedia', get: () -> return API.use.wikipedia.lookup this.queryParams,this.queryParams.type

API.add 'use/wikidata/:qid', get: () -> return API.use.wikidata.retrieve this.urlParams.qid,this.queryParams.all

API.add 'use/wikidata/find', get: () -> return API.use.wikidata.find this.queryParams.q,this.queryParams.url

API.add 'use/wikidata/properties', get: () -> return wikidata_properties

API.add 'use/wikidata/properties/:prop', get: () -> return wikidata_properties[this.urlParams.prop]


# https://en.wikinews.org/wiki/Category:Apple_Inc.
API.use.wikinews.about = (entity) ->
  # given the entity name, look up the wikinews category
  # get the list of all relevant articles
  # get all relevant articles, or just the list?
  # process them in some way?
  return

API.use.wikidata.retrieve = (qid,all) ->
  if not all
    exists = API.http.cache qid, 'wikidata_retrieve'
    return exists if exists
  try
    u = 'https://www.wikidata.org/wiki/Special:EntityData/' + qid + '.json'
    res = HTTP.call 'GET',u
    r = if all then res.data.entities[qid] else {}
    r.type = res.data.entities[qid].type
    r.qid = res.data.entities[qid].id
    r.label = res.data.entities[qid].labels?.en?.value
    r.description = res.data.entities[qid].descriptions?.en?.value
    r.wikipedia = res.data.entities[qid].sitelinks?.enwiki?.url
    r.wid = res.data.entities[qid].sitelinks?.enwiki?.url?.split('wiki/').pop()
    r.infokeys = []
    r.info = {}
    for c of res.data.entities[qid].claims
      claim = res.data.entities[qid].claims[c]
      wdp = wikidata_properties[c]
      wdp ?= c
      r.infokeys.push wdp
      #for s in claim, do something...
      r.info[wdp] = claim
    API.http.cache qid, 'wikidata_retrieve', r
    return r
  catch err
    return {}

API.use.wikidata.find = (entity,wurl,retrieve=true) ->
  res = {}
  entity ?= wurl?.split('wiki/').pop()
  w = API.use.wikipedia.lookup {title:entity}
  res.qid = w.data?.pageprops?.wikibase_item
  res.data = API.use.wikidata.retrieve(res.qid) if res.qid? and retrieve
  return res

# https://www.mediawiki.org/wiki/API:Main_page
# https://en.wikipedia.org/w/api.php

API.use.wikipedia.lookup = (opts,type) ->
  if not opts.titles and opts.title
    opts.titles = opts.title
    delete opts.title
  return {} if not opts.titles?
  titleparts = opts.titles.split(' ')
  titleparts[tp] = titleparts[tp][0].toUpperCase() + titleparts[tp].substring(1,titleparts[tp].length) for tp of titleparts
  opts.titles = encodeURIComponent(titleparts.join(' '))
  opts.action ?= 'query'
  opts.prop ?= 'revisions|pageprops'
  opts.rvprop ?= 'content'
  opts.format ?= 'json'
  # 'https://en.wikipedia.org/w/api.php?action=query&titles=' + encodeURIComponent(opts.title) + '&prop=pageprops&format=json'
  url = 'https://en.wikipedia.org/w/api.php?'
  url += o + '=' + opts[o] + '&' for o of opts
  try
    res = HTTP.call 'GET', url
    while res.data.query.normalized?.length
      url = url.replace(encodeURIComponent(res.data.query.normalized[0].from),encodeURIComponent(res.data.query.normalized[0].to))
      res = HTTP.call 'GET',url
    key
    disambiguation = []
    redirect = []
    key = k if key is undefined for k of res.data.query.pages
    while res.data.query.pages[key].revisions[0]['*'].indexOf('#REDIRECT') is 0 or res.data.query.pages[key].pageprops?.wikibase_item is 'Q224038'
      rv = res.data.query.pages[key].revisions[0]['*']
      if type and res.data.query.pages[key].pageprops?.wikibase_item is 'Q224038'
        type = 'organisation' if type is 'organization'
        type = type.toUpperCase()[0] + type.toLowerCase().substring(1,type.length)
        rv = rv.split('=='+type)[1].split('==\n')[1].split('\n==')[0]
        rvs = rv.split('[[')
        for ro in rvs
          if ro.indexOf(']]') isnt -1
            rvso = ro.split(']]')[0].replace(/ /g,'_')
            disambiguation.push(rvso) if disambiguation.indexOf(rsvo) is -1
      else if redirect.indexOf(res.data.query.pages[key].title) is -1
        redirect.push(res.data.query.pages[key].title)
      url = url.replace(encodeURIComponent(res.data.query.pages[key].title),encodeURIComponent(rv.split('[[')[1].split(']]')[0].replace(/ /g,'_')))
      res = HTTP.call 'GET',url
      key = undefined
      key = ki if key is undefined for ki of res.data.query.pages
    ret = {data:res.data.query.pages[key]}
    ret.disambiguation ?= disambiguation
    ret.redirect ?= redirect
    return ret
  catch err
    return {status:'error',data:err, error: err}

