
# https://arxiv.org/help/api/user-manual

API.use ?= {}
API.use.arxiv = {}

API.add 'use/arxiv', 
  get: () -> 
    return if this.queryParams.title then API.use.arxiv.title(this.queryParams.title, this.queryParams.format?) else API.use.arxiv.search this.queryParams.q, this.queryParams.format?

API.use.arxiv.search = (str,format,from,size) ->
  url = 'http://export.arxiv.org/api/query?search_query=all:' + str + '&sortBy=submittedDate&sortOrder=descending'
  # arxiv uses max_results and start, can provide a total of 30000, paged at most 2000 at a time - but will try to get whatever the max_results amount is
  if size
    sz = size
    sz += from if from
    url += '&max_results=' + sz
  url += '&start=' + from if from
  res = HTTP.call 'GET', url
  ret = API.convert.xml2json res.content, undefined, true #false
  try ret.total = ret.feed['opensearch:totalResults'][0].value
  try
    for e of ret.feed.entry
      try
        for l in ret.feed.entry[e].link
          if l.href.indexOf('/pdf/') isnt -1
            ret.feed.entry[e].pdf = l.href
          else if l.href.indexOf('/abs/') isnt -1
            ret.feed.entry[e].url = l.href
      try
        if format
          ret.feed.entry[e] = API.use.arxiv.format ret.feed.entry[e]
    if format
      ret.data = ret.feed.entry
      delete ret.feed
  return ret

API.use.arxiv.title = (title,format) ->
  try
    if title.indexOf(' AND ') is -1
      tt = ''
      tts = title.split ' '
      for tl in tts
        if tl.length > 2
          tt += ' AND ' if tt isnt ''
          tt += tl.replace(/-/g,' AND ')
    else
      tt = title
    res = API.use.arxiv.search tt, format
    rec = if res.data? then res.data[0] else res.feed.entry[0]
    return rec
  catch
    return undefined
    
API.use.arxiv.format = (rec, metadata={}) ->
  try metadata.title ?= rec.title
  try metadata.published ?= rec.published.split('T')[0]
  try metadata.year ?= metadata.published.split('-')[0]
  try metadata.abstract ?= rec.summary.replace(/\r?\n|\r/g,' ').trim()
  try
    metadata.author ?= []
    rec.author = [rec.author] if not _.isArray rec.author
    for a in rec.author
      as = a.name.split(' ')
      a.family = as[as.length-1]
      a.given = a.name.replace(a.family,'').trim()
      if a.affiliation?
        a.affiliation = a.affiliation[0] if _.isArray a.affiliation
        a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
      metadata.author.push a
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  try metadata.open ?= rec.open
  try metadata.redirect ?= rec.redirect
  return metadata
