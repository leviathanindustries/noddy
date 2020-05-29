

API.use ?= {}
API.use.wikipedia = {}
API.use.wikinews = {}

API.add 'use/wikipedia', get: () -> return API.use.wikipedia.lookup this.queryParams, this.queryParams.type

API.add 'use/wikinews', get: () -> return API.use.wikinews.about this.queryParams.qid, this.queryParams.q, this.queryParams.url, this.queryParams.text?
API.add 'use/wikinews/:qid', get: () -> return API.use.wikinews.about this.urlParams.qid, undefined, undefined, this.queryParams.text?
API.add 'use/wikinews/text/:qid', 
  get: () ->
    this.response.writeHead 200,
      'Content-type': 'text/html'
    this.response.end API.use.wikinews.about(this.urlParams.qid, undefined, undefined, true).text


# https://en.wikinews.org/wiki/Category:Apple_Inc.
API.use.wikinews.about = (qid, q, url, text=false) ->
  res = {}
  try res = API.use.wikidata.simplify qid, q, url
  try res.category = data["topic's main category"].replace('Category:','')
  res.news = []
  res.text = '' if text
  try
    if res.category? or res.label?
      pg = API.http.puppeteer 'https://en.wikinews.org/wiki/Category:' + (res.category ? res.label), 0
      pg = pg.split('wikidialog-alternative')[1].split('<ul>')[1].split('</ul>')[0]
      items = pg.split('</li>')
      for item in items
        try
          res.news.push
            date: item.split('<li>')[1].split(':')[0]
            title: item.split('title="')[1].split('"')[0]
            url: 'https://en.wikinews.org' + item.split('href="')[1].split('"')[0]
          if text
            res.text += '<br><br>' if res.text.length
            res.text += API.use.wikinews.article 'https://en.wikinews.org/' + item.split('href="')[1].split('"')[0]
  return res

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

# https://www.mediawiki.org/wiki/API:Main_page
# https://en.wikipedia.org/w/api.php
API.use.wikipedia.lookup = (opts,type,refresh=604800000) -> # default 7 day cache
  checksum = API.job.sign opts, type
  try
    if exists = API.http.cache checksum, 'wikipedia_lookup', undefined, refresh
      return exists

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
    disambiguation = []
    redirect = []
    for k of res.data.query.pages
      key = k if key is undefined
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
      for ki of res.data.query.pages
        key ?= ki
    ret = {data:res.data.query.pages[key]}
    ret.disambiguation ?= disambiguation
    ret.redirect ?= redirect
    try API.http.cache checksum, 'wikipedia_lookup', ret
    return ret
  catch err
    return {status:'error',data:err, error: err}

