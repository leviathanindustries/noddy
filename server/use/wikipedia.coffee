

API.use ?= {}
API.use.wikipedia = {}
API.use.wikidata = {}
API.use.wikinews = {}

API.add 'use/wikipedia', get: () -> return API.use.wikipedia.lookup this.queryParams, this.queryParams.type

API.add 'use/wikidata/:qid', get: () -> return API.use.wikidata.retrieve this.urlParams.qid, this.queryParams.all

API.add 'use/wikidata/find', get: () -> return API.use.wikidata.find this.queryParams.q, this.queryParams.url

API.add 'use/wikidata/simplify', get: () -> return API.use.wikidata.simplify this.queryParams.qid, this.queryParams.q, this.queryParams.url
API.add 'use/wikidata/simplify/:qid', get: () -> return API.use.wikidata.simplify this.urlParams.qid

API.add 'use/wikidata/properties', get: () -> return wikidata_properties

API.add 'use/wikidata/properties/:prop', get: () -> return wikidata_properties[this.urlParams.prop]

API.add 'use/wikinews', get: () -> return API.use.wikinews.about this.queryParams.qid, this.queryParams.q, this.queryParams.url, this.queryParams.text?
API.add 'use/wikinews/:qid', get: () -> return API.use.wikinews.about this.urlParams.qid, undefined, undefined, this.queryParams.text?
API.add 'use/wikinews/text/:qid', 
  get: () ->
    this.response.writeHead 200,
      'Content-type': 'text/html'
    this.response.end API.use.wikinews.about(this.urlParams.qid, undefined, undefined, true).text
    this.done()


# https://en.wikinews.org/wiki/Category:Apple_Inc.
API.use.wikinews.about = (qid, q, url, text=false) ->
  news = {news: []}
  try
    data = API.use.wikidata.simplify qid, q, url
    news.category = data["topic's main category"].replace('Category:','')
    news.label = data.label
    news.qid = data.qid
    news.text = '' if text
    if news.category?
      pg = API.http.puppeteer 'https://en.wikinews.org/wiki/Category:' + news.category, 0
      pg = pg.split('wikidialog-alternative')[1].split('<ul>')[1].split('</ul>')[0]
      items = pg.split('</li>')
      for item in items
        try
          news.news.push
            date: item.split('<li>')[1].split(':')[0]
            title: item.split('title="')[1].split('"')[0]
            url: 'https://en.wikinews.org' + item.split('href="')[1].split('"')[0]
          if text
            news.text += '<br><br>' if news.text.length
            news.text += API.use.wikinews.article 'https://en.wikinews.org/' + item.split('href="')[1].split('"')[0]
  return news

API.use.wikinews.article = (url) ->
  article = ''
  txt = API.http.puppeteer url, 0
  txt = txt.split('id="firstHeading"')[1].split('id="Related_articles"')[0]
  article += '<h2><a target="_blank" href="' + url + '">' + txt.split('>')[1].split('<')[0] + '</a></h2>'
  paras = txt.split('<p>')
  paras.shift()
  article += '<p>' if paras.length
  for para in paras
    article += para.split('</p>')[0] + '</p>'
  article += '</p>' if paras.length
  return article

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

API.use.wikidata.drill = (qid) ->
  return undefined if not qid?
  console.log 'drilling ' + qid
  #res = {}
  try
    data = API.use.wikidata.retrieve qid
    return data.label
    #res.type = data.type
    #res.label = data.label
    #res.description = data.description
    #res.wikipedia = data.wikipedia
    #res.wid = data.wid
    # how deep can this safely run, does it loop?
    #for key in data.infokeys
    #  try
    #    res[key] = API.use.wikidata.drill data.info[key][0].mainsnak.datavalue.value.id
  #return res
  
API.use.wikidata.simplify = (qid,q,url) ->
  res = {}
  if qid
    res.qid = qid
    data = API.use.wikidata.retrieve qid
  else
    q ?= url?.split('wiki/').pop()
    w = API.use.wikipedia.lookup {title:q}
    res.qid = w.data?.pageprops?.wikibase_item
    data = API.use.wikidata.retrieve(res.qid) if res.qid?
  if data
    res.type = data.type
    res.label = data.label
    res.description = data.description
    res.wikipedia = data.wikipedia
    res.wid = data.wid
    for key in data.infokeys
      try
        dk = API.use.wikidata.drill data.info[key][0].mainsnak.datavalue.value.id
        res[key] = dk if dk
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

