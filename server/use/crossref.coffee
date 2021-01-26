
import moment from 'moment'
import Future from 'fibers/future'


# a crossref API client
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

# crossref now prefers some identifying headers
header = {
  #'User-Agent': (API.settings.name ? 'noddy') + ' v' + (API.settings.version ? '0.0.1') + (if API.settings.dev then 'd' else '') + ' (https://cottagelabs.com; mailto:' + (API.settings.log?.to ? 'mark@cottagelabs.com') + ')'
  'User-Agent': 'OAB; mailto: joe@openaccessbutton.org'
}

API.use ?= {}
API.use.crossref = {works:{},journals:{}, publishers: {}, funders: {}}

@crossref_journal = new API.collection {index:"crossref", type:"journal"}
@crossref_works = new API.collection {index:"crossref", type:"works", devislive:true}
@crossref_extra = new API.collection {index:"crossref", type:"extra", devislive:true}



API.add 'use/crossref/works',
  get: () -> 
    if this.queryParams.title and ct = API.use.crossref.works.title this.queryParams.title, this.queryParams.format
      return ct
    else if this.queryParams.doi and dt = API.use.crossref.works.doi this.queryParams.doi, this.queryParams.format
      return dt
    else
      return crossref_works.search this.queryParams

API.add 'use/crossref/works/:doipre/:doipost',
  get: () -> return API.use.crossref.works.doi this.urlParams.doipre + '/' + this.urlParams.doipost, this.queryParams.format
# there are DOIs that can have slashes within their second part and are valid. Possibly could have more than one slash
# and there does not seem to be a way to pass wildcards to the urlparams to match multiple / routes
# so this will do for now...
API.add 'use/crossref/works/:doipre/:doipost/:doimore',
  get: () -> return API.use.crossref.works.doi this.urlParams.doipre + '/' + this.urlParams.doipost + '/' + this.urlParams.doimore, this.queryParams.format

API.add 'use/crossref/works/extra', () -> return crossref_extra.search this.queryParams

API.add 'use/crossref/works/search',
  get: () -> return API.use.crossref.works.search (this.queryParams.q ? this.queryParams.query), undefined, undefined, (this.queryParams.from ? this.queryParams.offset ? this.queryParams.cursor), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format
API.add 'use/crossref/works/searchby/:searchby', # can be published, indexed, deposited, created
  get: () -> return API.use.crossref.works.searchby this.urlParams.searchby, (this.queryParams.q ? this.queryParams.query), undefined, undefined, (this.queryParams.from ? this.queryParams.offset ? this.queryParams.cursor), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format
API.add 'use/crossref/works/searchby/:searchby/:startdate',
  get: () -> return API.use.crossref.works.searchby this.urlParams.searchby, (this.queryParams.q ? this.queryParams.query), this.urlParams.startdate, undefined, (this.queryParams.from ? this.queryParams.offset ? this.queryParams.cursor), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format
API.add 'use/crossref/works/searchby/:searchby/:startdate/:enddate',
  get: () -> return API.use.crossref.works.searchby this.urlParams.searchby, (this.queryParams.q ? this.queryParams.query), this.urlParams.startdate, this.urlParams.enddate, (this.queryParams.from ? this.queryParams.offset ? this.queryParams.cursor), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter, this.queryParams.order, this.queryParams.format

API.add 'use/crossref/works/index', 
  get: () -> 
    Meteor.setTimeout (() => API.use.crossref.works.index(this.queryParams.lts, this.queryParams.by)), 1
    return true
API.add 'use/crossref/works/lastindex', get: () -> return API.use.crossref.works.lastindex()
API.add 'use/crossref/works/lastindex/count', get: () -> return API.use.crossref.works.lastindex true
#API.add 'use/crossref/works/import', post: () -> return API.use.crossref.works.import this.request.body

API.add 'use/crossref/types',
  get: () -> return API.use.crossref.types()

API.add 'use/crossref/journals', () -> crossref_journal.search this

API.add 'use/crossref/journals/import',
  get: 
    roleRequired: if API.settings.dev then undefined else 'crossref.admin'
    action:() -> 
      Meteor.setTimeout (() => API.use.crossref.journals.import()), 1
      return true

API.add 'use/crossref/journals/:issn',
  get: () -> return API.use.crossref.journals.issn this.urlParams.issn
API.add 'use/crossref/journals/:issn/works',
  get: () -> return API.use.crossref.works.issn this.urlParams.issn, this.queryParams
API.add 'use/crossref/journals/:issn/doi',
  get: () -> return API.use.crossref.journals.doi this.urlParams.issn
API.add 'use/crossref/journals/:issn/dois',
  get: () -> return API.use.crossref.journals.dois this.urlParams.issn, this.queryParams.from

API.add 'use/crossref/publishers',
  get: () -> return API.use.crossref.publishers.search (this.queryParams.q ? this.queryParams.query), (this.queryParams.from ? this.queryParams.offset), (this.queryParams.size ? this.queryParams.rows), this.queryParams.filter

API.add 'use/crossref/reverse',
  get: () -> return API.use.crossref.reverse [this.queryParams.q ? this.queryParams.query ? this.queryParams.title], this.queryParams.score, this.queryParams.format
  post: () -> return API.use.crossref.reverse this.request.body

API.add 'use/crossref/resolve', get: () -> return API.use.crossref.resolve this.queryParams.doi
API.add 'use/crossref/resolve/:doipre/:doipost', get: () -> return API.use.crossref.resolve this.urlParams.doipre + '/' + this.urlParams.doipost
API.add 'use/crossref/resolve/:doipre/:doipost/:doimore', get: () -> return API.use.crossref.resolve this.urlParams.doipre + '/' + this.urlParams.doipost + '/' + this.urlParams.doimore



API.use.crossref.types = () ->
  url = 'https://api.crossref.org/types'
  API.log 'Using crossref for ' + url
  try
    res = HTTP.call 'GET', url, {headers: header}
    if res.statusCode is 200
      return res.data.message.items
    else
      return undefined

API.use.crossref.reverse = (citations, score=85, format=false) ->
  citations = [citations] if typeof citations is 'string'
  url = 'https://api.crossref.org/reverse'
  API.log 'Using crossref for ' + url + ' with citation ' + JSON.stringify citations
  try
    res = HTTP.call 'POST', url, {data:citations, headers: header}
    if res.statusCode is 200
      if res?.data?.message?.DOI and res.data.message.score and res.data.message.type is 'journal-article'
        sc = res.data.message.score
        if sc < score
          ignore = ["a","an","and","are","as","at","but","be","by","do","for","if","in","is","it","or","so","the","to"]
          titleparts = res.data.message.title[0].toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9]/g,' ').split(' ')
          titles = []
          for f in titleparts
            titles.push(f) if ignore.indexOf(f.split("'")[0]) is -1 and f.length > 0
          citeparts = citations.join(' ').toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9]/g,' ').replace(/  /g,' ').split(' ')
          cites = []
          for c in citeparts
            cites.push(c) if ignore.indexOf(c.split("'")[0]) is -1 and c.length > 1
          bonus = (score - sc)/titles.length + 1
          found = []
          for w in titles
            found.push(w) if w in cites
          sc += bonus * found.length if titles.length is found.length and found.join() is titles.join()
        if sc >= score
          if format
            return API.use.crossref.works.format res.data.message
          else
            return { data: {doi:res.data.message.DOI, title:res.data.message.title[0], received:res.data.message.score, adjusted: sc}, original:res.data}
        else
          return { data: {info: 'below score', received:res.data.message.score, adjusted: sc}, original:res.data}
      else
        return {}
    else
      return { status: 'error', data: res }
  catch err
    return { status: 'error', error: err.toString() }

API.use.crossref.resolve = (doi) ->
  doi = doi.replace('http://','').replace('https://','').replace('dx.doi.org/','').replace('doi.org/','')
  cached = API.http.cache doi, 'crossref_resolve'
  if cached
    return cached
  else
    url = false
    try
      # TODO NOTE that the URL given by crossref doi resolver may NOT be the final resolved URL. The publisher may still redirect to a different one
      resp = HTTP.call 'GET', 'https://doi.org/api/handles/' + doi, {headers: header}
      for r in resp.data?.values
        if r.type.toLowerCase() is 'url'
          url = r.data.value
          # like these weird chinese ones, which end up throwing 404 anyway, but, just in case - https://doi.org/api/handles/10.7688/j.issn.1000-1646.2014.05.20
          url = new Buffer(url,'base64').toString('utf-8') if r.data.format is 'base64'
          API.http.cache doi, 'crossref_resolve', url
    return url



API.use.crossref.journals.issn = (issn) ->
  issn = issn.split(',') if typeof issn is 'string'
  issn = [issn] if typeof issn is 'string'
  return crossref_journal.find 'ISSN.exact:"' + issn.join('" OR ISSN.exact:"') + '"'

API.use.crossref.journals.doi = (issn) ->
  issn = issn.split(',') if typeof issn is 'string'
  issn = [issn] if typeof issn is 'string'
  try
    return crossref_works.find('ISSN.exact:"' + issn.join('" OR issn.exact:"') + '"', {include: 'DOI', sort: {publishedAt:{order:'asc'}}}).DOI
  catch
    return undefined

API.use.crossref.journals.dois = (issn, from=0) ->
  issn = issn.split(',') if typeof issn is 'string'
  issn = [issn] if typeof issn is 'string'
  dois = []
  crossref_works.each 'ISSN.exact:"' + issn.join('" OR issn.exact:"') + '"', {from: from, include: 'DOI', sort: {publishedAt:{order:'desc'}}}, (rec) ->
    dois.push rec.DOI
    if dois.length >= 10000
      return 'break'
  return dois

API.use.crossref.journals.search = (qrystr, from, size, filter) ->
  url = 'https://api.crossref.org/journals?'
  if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'').replace(/ AND /g,'+').replace(/ OR /g,' ').replace(/ NOT /g,'-').replace(/ /g,'+')
    url += 'query=' + qry
  url += '&offset=' + from if from?
  url += '&rows=' + size if size?
  url += '&filter=' + filter if filter?
  url = url.replace('?&','?') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  API.log 'Using crossref for ' + url
  try res = HTTP.call 'GET', url, {headers: header}
  return if res?.statusCode is 200 then { total: res.data.message['total-results'], data: res.data.message.items, facets: res.data.message.facets} else { status: 'error', data: res}

API.use.crossref.journals.import = () ->
  started = Date.now()
  size = 1000
  total = 0
  counter = 0
  journals = 0
  batch = []
  
  while total is 0 or counter < total
    if batch.length >= 10000
      crossref_journal.insert batch
      batch = []

    try
      crls = API.use.crossref.journals.search undefined, counter, size
      total = crls.total if total is 0
      for crl in crls?.data ? []
        journals += 1
        batch.push crl
      counter += size
    catch err
      console.log 'crossref journals import process error'
      try
        console.log err.toString()
      catch
        try console.log err
      future = new Future()
      Meteor.setTimeout (() -> future.return()), 2000 # wait 2s on crossref downtime
      future.wait()

  crossref_journal.insert(batch) if batch.length
  crossref_journal.remove 'createdAt:<' + started
  API.log 'Retrieved and imported ' + journals + ' crossref journals'
  return journals



API.use.crossref.publishers.search = (qrystr, from, size, filter) ->
  url = 'https://api.crossref.org/members?'
  if qrystr and qrystr isnt 'all'
    url += 'query=' + encodeURIComponent qrystr
  url += '&offset=' + from if from?
  url += '&rows=' + size if size?
  url += '&filter=' + filter if filter?
  url = url.replace('?&','?')
  API.log 'Using crossref for ' + url
  res = HTTP.call 'GET', url, {headers: header}
  return if res.statusCode is 200 then { total: res.data.message['total-results'], data: res.data.message.items, facets: res.data.message.facets} else { status: 'error', data: res}

API.use.crossref.funders.search = (qrystr, from, size, filter) ->
  url = 'https://api.crossref.org/funders?'
  if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/ /g,'+')
    url += 'query=' + qry
  url += '&offset=' + from if from?
  url += '&rows=' + size if size?
  url += '&filter=' + filter if filter?
  url = url.replace('?&','?')
  API.log 'Using crossref for ' + url
  res = HTTP.call 'GET', url, {headers: header}
  return if res.statusCode is 200 then { total: res.data.message['total-results'], data: res.data.message.items, facets: res.data.message.facets} else { status: 'error', data: res}


API.use.crossref.works.issn = (issn, q={}) ->
  q = {format: true} if q is true
  format = if q.format then true else false
  delete q.format
  issn = [issn] if typeof issn is 'string'
  return crossref_works.search q, restrict: [{query_string: {query: 'ISSN.exact:"' + issn.join('" OR issn.exact:"') + '"'}}]

API.use.crossref.works.doi = (doi, format) ->
  ret = crossref_works.get doi.toLowerCase().replace /\//g, '_'
  if not ret?
    url = 'https://api.crossref.org/works/' + doi
    API.log 'Using crossref for ' + url
    try res = HTTP.call 'GET', url, {headers: header}
    if res?.statusCode is 200 and res.data?.message?.DOI?
      rec = res.data.message
      if rec.relation? or rec.reference? or rec.abstract?
        rt = _id: rec.DOI.replace(/\//g, '_'), relation: rec.relation, reference: rec.reference, abstract: rec.abstract
        if ext = crossref_extra.get rt._id
          upd = {}
          upd.relation = rec.relation if rec.relation? and not ext.relation?
          upd.reference = rec.reference if rec.reference? and not ext.reference?
          upd.abstract = rec.abstract if rec.abstract? and not ext.abstract?
          if typeof upd.abstract is 'string'
            upd.abstract = API.convert.html2txt upd.abstract
          if JSON.stringify(upd) isnt '{}'
            crossref_extra.update rt._id, upd
        else
          crossref_extra.insert rt
      ret = API.use.crossref.works.clean rec
      API.log 'Saved crossref work ' + ret.DOI
      crossref_works.insert ret
  return if not ret? then undefined else if format then API.use.crossref.works.format(ret) else ret

API.use.crossref.works.title = (title, format) ->
  metadata = if typeof title is 'object' then title else {}
  title = metadata.title if typeof title is 'object'
  return undefined if typeof title isnt 'string'
  qr = 'title.exact:"' + title + '"'
  if title.indexOf(' ') isnt -1
    qr += ' OR ('
    f = true
    for t in title.split ' '
      if t.length > 2
        if f is true
          f = false
        else
          qr += ' AND '
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")'
    qr += ')'
  res = crossref_works.search qr, 20
  possible = false
  if res?.hits?.total
    ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
    for r in res.hits.hits
      rec = r._source
      rt = (if typeof rec.title is 'string' then rec.title else rec.title[0]).toLowerCase()
      if rec.subtitle?
        st = (if typeof rec.subtitle is 'string' then rec.subtitle else rec.subtitle[0]).toLowerCase()
        rt += ' ' + st if typeof st is 'string' and st.length and st not in rt
      rt = rt.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
      if (ltitle.indexOf(rt) isnt -1 or rt.indexOf(ltitle) isnt -1) and ltitle.length/rt.length > 0.7 and ltitle.length/rt.length < 1.3
        matches = true
        fr = API.use.crossref.works.format rec
        for k of metadata
          if k not in ['citation','title'] and typeof metadata[k] in ['string','number']
            matches = not fr[k]? or typeof fr[k] not in ['string','number'] or fr[k].toLowerCase() is metadata[k].toLowerCase()
        if matches
          if rec.type is 'journal-article'
            return if format then API.use.crossref.works.format(rec) else rec
          else if possible is false or possible.type isnt 'journal-article' and rec.type is 'journal-article'
            possible = rec
  return if possible is false then undefined else if format then API.use.crossref.works.format(possible) else match

# from could also be a cursor value, use * to start a cursor then return the next-cursor given in the response object
# largest size is 1000 and deepest from is 10000, so anything more than that needs cursor
API.use.crossref.works.search = (qrystr, from, size, filter, sort, order='desc', format, funder, publisher, journal) ->
  # max size is 1000
  url = 'https://api.crossref.org'
  url += '/funders/' + funder if funder # crossref funder ID
  url += '/members/' + publisher if publisher # crossref publisher ID
  url += '/journals/' + journal if journal # journal issn
  url += '/works?'
  url += 'sort=' + sort + '&order=' + order + '&' if sort?
  # more specific queries can be made using:
  #query.container-title	Query container-title aka. publication name
  #query.author	Query author given and family names
  #query.editor	Query editor given and family names
  #query.chair	Query chair given and family names
  #query.translator	Query translator given and family names
  #query.contributor	Query author, editor, chair and translator given and family names
  #query.bibliographic	Query bibliographic information, useful for citation look up. Includes titles, authors, ISSNs and publication years
  #query.affiliation  Query contributor affiliations
  # note there is not a "title" one - just use bibliographic. bibliographic is titles, authors, ISSNs, and publication years
  # ALSO NOTE: crossref LOOKS like it uses logica + and - operators, but it doesn't. their examples use + instaed of space, but either seems to make no difference
  # + or - or space, all just result in OR queries, with increasing large result sets
  if typeof qrystr is 'object'
    for k of qrystr
      if k not in ['from','size','filter','sort','order','format','funder','publisher','journal','issn'] or (k is 'funder' and not funder?) or (k is 'publisher' and not publisher?) or (k in ['issn','journal'] and not journal?)
        ky = if k in ['title','citation','issn'] then 'query.bibliographic' else if k is 'journal' then 'query.container-title' else if k in ['author','editor','chair','translator','contributor','affiliation','bibliographic'] then 'query.' + k else k
        url += ky + '=' + encodeURIComponent(qrystr[k]) + '&' 
  else if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'') #.replace(/ AND /g,'+').replace(/ NOT /g,'-')
    #qry = if qry.indexOf(' OR ') isnt -1 then qry.replace(/ OR /g,' ') else qry.replace(/ /g,'+')
    qry = qry.replace(/ /g,'+')
    url += 'query=' + encodeURIComponent(qry) + '&'
  if from?
    if from isnt '*' and typeof from is 'string' and not from.replace(/[0-9]/g,'').length
      try
        fp = parseInt from
        from = fp if not isNaN fp
    if typeof from isnt 'number'
      url += 'cursor=' + encodeURIComponent(from) + '&'
    else
      url += 'offset=' + from + '&'
  url += 'rows=' + size + '&' if size?
  url += 'filter=' + encodeURIComponent(filter) + '&'if filter? and filter isnt ''
  url = url.replace('?&','?').replace(/&$/,'') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  API.log 'Using crossref for ' + url
  try res = HTTP.call 'GET', url, {headers: header}
  if res?.statusCode is 200
    ri = res.data.message.items
    if format
      for r of ri
        ri[r] = API.use.crossref.works.format ri[r]
    return { total: res.data.message['total-results'], cursor: res.data.message['next-cursor'], data: ri, facets: res.data.message.facets}
  else
    return { status: 'error', data: res}

API.use.crossref.works.searchby = (searchby='published', qrystr, startdate, enddate, from, size, filter, order, format) ->
  # can be published, indexed, deposited, created
  # using ?filter=from-pub-date:2004-04-04,until-pub-date:2004-04-04 (the dates are inclusive)
  part = if searchby is 'published' then 'pub' else if searchby is 'created' then 'created' else searchby.replace('ed','')
  if filter? then filter += ',' else filter = ''
  if startdate
    startdate = moment(startdate).format('YYYY-MM-DD') if typeof startdate isnt 'string' or startdate.indexOf('-') is -1 or startdate.length > 4
    filter += 'from-' + part + '-date:' + startdate
  if enddate
    enddate = moment(enddate).format('YYYY-MM-DD') if typeof enddate isnt 'string' or enddate.indexOf('-') is -1 or enddate.length > 4
    filter += ',until-' + part + '-date:' + enddate
  return API.use.crossref.works.search qrystr, from, size, filter, searchby, order, format

API.use.crossref.works.index = (lts, searchby='indexed') ->
  if not lts and last = API.http.cache 'last', 'crossref_works_imported'
    # just in case it is an old reading from before I had to switch to using cursor, I was storing the last from number too
    lts = if typeof last is 'string' then parseInt(last.split('_')[0]) else last
    console.log 'Set crossref works index import from cached last date'
    console.log lts, moment(lts).startOf('day').format('YYYY-MM-DD')
  else
    lts = 1585971669199 # the timestamp of the last article from the data dump (around 4th April 2020)
  startday = moment(lts).startOf('day').valueOf()
  dn = Date.now()
  loaded = 0
  updated = 0
  days = 0
  broken = false
  try
    target = API.use.crossref.works.searchby(searchby, undefined, startday, undefined, undefined, 10).total
    console.log target
  catch
    target = 0
  while not broken and startday < dn
    cursor = '*' # set a new cursor on each index day query
    console.log startday
    days += 1
    totalthisday = false
    fromthisday = 0
    while not broken and (totalthisday is false or fromthisday < totalthisday)
      console.log loaded, fromthisday, target, searchby
      console.log cursor
      try
        thisdays = API.use.crossref.works.searchby searchby, undefined, startday, startday, cursor, 1000, undefined, 'asc' # using same day for crossref API gets that whole day
        console.log thisdays.data.length
        batch = []
        xtb = []
        for rec in thisdays.data
          if not rec.DOI
            console.log rec
          if rec.relation? or rec.reference? or rec.abstract?
            rt = _id: rec.DOI.replace(/\//g, '_'), relation: rec.relation, reference: rec.reference, abstract: rec.abstract
            if ext = crossref_extra.get rt._id
              upd = {}
              upd.relation = rec.relation if rec.relation? and not ext.relation?
              upd.reference = rec.reference if rec.reference? and not ext.reference?
              upd.abstract = rec.abstract if rec.abstract? and not ext.abstract?
              if typeof upd.abstract is 'string'
                upd.abstract = API.convert.html2txt upd.abstract
              if JSON.stringify(upd) isnt '{}'
                crossref_extra.update rt._id, upd
            else
              xtb.push rt
          cr = API.use.crossref.works.clean rec
          updated += 1 if crossref_works.get cr._id
          batch.push cr
        if batch.length
          l = crossref_works.insert batch
          if l?.records is batch.length
            loaded += l.records
            API.http.cache 'last', 'crossref_works_imported', startday #+ '_' + fromthisday
          else
            broken = true
        if xtb.length
          try crossref_extra.insert xtb
        if totalthisday is false
          totalthisday = thisdays?.total ? 0
        fromthisday += 1000
        cursor = thisdays.cursor if thisdays?.cursor?
      catch err
        console.log 'crossref index process error'
        try
          console.log err.toString()
        catch
          try console.log err
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 2000 # wait 2s on crossref downtime
        future.wait()
    startday += 86400000

  API.mail.send
    service: 'openaccessbutton'
    from: 'natalia.norori@openaccessbutton.org'
    to: if broken then 'alert@cottagelabs.com' else 'mark@cottagelabs.com'
    subject: 'Crossref index check ' + (if broken then 'broken' else 'complete')
    text: 'Processed ' + days + ' days up to ' + startday + ' and loaded ' + loaded + ' records of which ' + updated + ' were updates. Target was ' + target
  return loaded

API.use.crossref.works.lastindex = (count) ->
  try
    last = API.http.cache 'last', 'crossref_works_imported'
    lts = if typeof last is 'string' then parseInt(last.split('_')[0]) else last
  catch
    lts = 1585971669199 # the timestamp of the last article from the data dump (around 4th April 2020)
  if count
    res = date: moment(lts).startOf('day').format('YYYY-MM-DD')
    res.timestamp = moment(lts).startOf('day').valueOf()
    res[p] = API.use.crossref.works.searchby(p, undefined, res.timestamp).total for p in ['published', 'indexed', 'deposited', 'created']
    return res
  else
    return moment(lts).startOf('day').format('YYYY-MM-DD')

API.use.crossref.works.clean = (rec) ->
  rec._id = rec.DOI.replace /\//g, '_'
  delete rec.reference
  delete rec.relation
  delete rec.abstract
  for p in ['published-print','published-online','issued','deposited','indexed']
    if rec[p]
      if rec[p]['date-time'] and rec[p]['date-time'].split('T')[0].split('-').length is 3
        rec.published ?= rec[p]['date-time'].split('T')[0]
        rec.year ?= rec.published.split('-')[0] if rec.published?
      pbl = ''
      if rec[p]['date-parts'] and rec[p]['date-parts'].length and rec[p]['date-parts'][0] and (not rec.published or not rec[p].timestamp)
        rp = rec[p]['date-parts'][0] #crossref uses year month day in a list
        pbl = rp[0]
        if rp.length is 1
          pbl += '-01-01'
        else
          pbl += if rp.length > 1 then '-' + (if rp[1].toString().length is 1 then '0' else '') + rp[1] else '-01'
          pbl += if rp.length > 2 then '-' + (if rp[2].toString().length is 1 then '0' else '') + rp[2] else '-01'
        if not rec.published
          rec.published = pbl
          rec.year = pbl.split('-')[0]
        if not rec[p].timestamp and pbl
          rec[p].timestamp = moment(pbl,'YYYY-MM-DD').valueOf()
        rec.publishedAt ?= rec[p].timestamp
        
  for a in rec.assertion ? []
    if a.label is 'OPEN ACCESS'
      if a.URL and a.URL.indexOf('creativecommons') isnt -1
        rec.license ?= []
        rec.license.push {'URL': a.URL}
      rec.is_oa = true

  for l in rec.license ? []
    if l.URL and l.URL.indexOf('creativecommons') isnt -1 and (not rec.licence or rec.licence.indexOf('creativecommons') is -1)
      rec.licence = l.URL
      rec.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/$\//,'').replace(/\//g, '-') if rec.licence.indexOf('/licenses/') isnt -1
      rec.is_oa = true
  return rec
  
API.use.crossref.works.format = (rec, metadata={}) ->
  try metadata.title = rec.title[0]
  try
    if rec.subtitle? and rec.subtitle.length and rec.subtitle[0].length
      metadata.title += ': ' + rec.subtitle[0] 
  try metadata.doi = rec.DOI if rec.DOI?
  try metadata.doi = rec.doi if rec.doi? # just in case
  try metadata.crossref_type = rec.type
  try metadata.author = rec.author if rec.author?
  if metadata.author
    for a in metadata.author
      a.name = a.family + ' ' + a.given if not a.name? and a.family and a.given
      if a.affiliation?
        a.affiliation = a.affiliation[0] if _.isArray a.affiliation
        a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
        try a.affiliation.name = a.affiliation.name.replace(/\s\s+/g,' ').trim()
  try metadata.journal = rec['container-title'][0]
  try metadata.journal_short = rec['short-container-title'][0]
  try metadata.issue = rec.issue if rec.issue?
  try metadata.volume = rec.volume if rec.volume?
  try metadata.page = rec.page.toString() if rec.page?
  try metadata.issn = _.uniq rec.ISSN
  try metadata.keyword = rec.subject if rec.subject? # is a list of strings - goes in keywords because subject was already previously used as an object
  try metadata.publisher = rec.publisher if rec.publisher?
  for p in ['published-print','journal-issue.published-print','issued','published-online','created','deposited']
    try
      if rt = rec[p] ? rec['journal-issue']?[p.replace('journal-issue.','')]
        if typeof rt['date-time'] is 'string' and rt['date-time'].indexOf('T') isnt -1 and rt['date-time'].split('T')[0].split('-').length is 3
          metadata.published = rt['date-time'].split('T')[0]
          metadata.year = metadata.published.split('-')[0]
          break
        else if rt['date-parts']? and rt['date-parts'].length and _.isArray(rt['date-parts'][0]) and rt['date-parts'][0].length
          rp = rt['date-parts'][0]
          pbl = rp[0].toString()
          if pbl.length > 2 # needs to be a year
            metadata.year ?= pbl
            if rp.length is 1
              pbl += '-01-01'
            else
              m = false
              d = false
              if not isNaN(parseInt(rp[1])) and parseInt(rp[1]) > 12
                d = rp[1].toString()
              else
                m = rp[1].toString()
              if rp.length is 2
                if d isnt false
                  m = rp[2].toString()
                else
                  d = rp[2].toString()
              m = if m is false then '01' else if m.length is 1 then '0' + m else m
              d = if d is false then '01' else if d.length is 1 then '0' + d else d
              pbl += '-' + m + '-' + d
            metadata.published = pbl
            break
  try metadata.abstract = API.convert.html2txt(rec.abstract).replace(/\n/g,' ') if rec.abstract?
  try
    if rec.reference? and rec.reference.length
      metadata.reference ?= []
      for r in rec.reference
        rf = {}
        rf.doi = r.DOI if r.DOI?
        rf.title = r.article-title if r.article-title?
        rf.journal = r.journal-title if r.journal-title?
        metadata.reference.push(rf) if not _.isEmpty rf
  try
    if rec.license?
      for l in rec.license
        if typeof l.URL is 'string' and (typeof metadata.licence isnt 'string' or (metadata.licence.indexOf('creativecommons') is -1 and l.URL.indexOf('creativecommons') isnt -1))
          metadata.licence = l.URL
          if l.URL.indexOf('creativecommons') isnt -1
            md = 'https://doi.org/' + metadata.doi
            metadata.url ?= md
            metadata.url.push(md) if _.isArray(metadata.url) and md not in metadata.url
            try metadata.redirect = API.service.oab.redirect md
            break
  return metadata  

API.use.crossref.works.import = (recs) ->
  if _.isArray(recs) and recs.length
    return crossref_works.insert recs
  else
    return undefined

_xref_import = () ->
  if API.settings.cluster?.ip? and API.status.ip() not in API.settings.cluster.ip and API.settings.dev
    API.log 'Setting up a crossref journal import to run every week on ' + API.status.ip()
    Meteor.setInterval API.use.crossref.journals.import, 604800000
    API.log 'Setting up a crossref works import to run every day on ' + API.status.ip()
    Meteor.setInterval (() -> API.use.crossref.works.index(undefined, 'indexed')), 86400000
Meteor.setTimeout _xref_import, 19000



API.use.crossref.status = () ->
  try
    res = HTTP.call 'GET', 'https://api.crossref.org/works/10.1186/1758-2946-3-47', {headers: header, timeout: API.settings.use?.crossref?.timeout ? API.settings.use?._timeout ? 4000}
    return if res.statusCode is 200 and res.data.status is 'ok' then true else res.data
  catch err
    return err.toString()

