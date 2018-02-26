

import fs from 'fs'

API.add 'service/lantern/licence',
  get: () -> return if this.queryParams.url then API.academic.licence(this.queryParams.url) else data: 'Find the licence of a URL'
  post: () -> return API.academic.licence this.request.body.url

API.add 'service/lantern/licences', get: () -> return API.academic.licences()

API.service.lantern.licences = () ->
  # licences originally derived from http://licenses.opendefinition.org/licenses/groups/all.json
  localcopy = API.settings.service?.lantern?.licence?.file
  stale = API.settings.service?.lantern?.licence?.stale
  if fs.existsSync(localcopy) and ( ( (new Date()) - fs.statSync(localcopy).mtime) < stale or not API.settings.service?.lantern?.licence?.remote)
    return JSON.parse fs.readFileSync(localcopy)
  else if API.settings.service?.lantern?.licence?.remote
    try
      API.log 'Getting remote licences file for lantern licence check'
      g = HTTP.call 'GET', API.settings.service.lantern.licence.remote
      sheet = g.data.feed.entry
      # sort longest matchtext first
      licences = []
      for l in sheet
        if l.gsx$matchtext?.$t? and l.gsx$matchtext.$t.length > 0 and l.gsx$licencetype?.$t?
          licences.push { match: l.gsx$matchtext.$t, domain: l.gsx$matchesondomains?.$t, licence: l.gsx$licencetype.$t }
      licences.sort (a, b) -> return b.match.length - a.match.length
      fs.writeFileSync localcopy, JSON.stringify(licences)
      return licences
    catch
      return []

API.service.lantern.licence = (url,resolve=false,content,start,end) ->
  API.log msg: 'Lantern finding licence', url: url, resolve: resolve, content: content?, start: start, end: end
  url = url.replace(/(^\s*)|(\s*$)/g,'') if url?
  resolved = url
  if resolve and url
    if API.service.oab?
      tr = API.service.oab.resolve url
      resolved = if typeof tr.redirect is 'string' then tr.redirect else (if tr.url then tr.url else url)
    else
      resolved = API.http.resolve url
  content ?= API.http.phantom resolved
  content = undefined if typeof content is 'number'

  lic = {}
  lic.url = url if url?
  lic.resolved = resolved if resolve and resolved?
  if content?
    licences = API.service.lantern.licences()
    content = content.split(start)[1] if start? and content.indexOf(start) isnt -1
    content = content.split(end)[0] if end?
    if content.length > 1000000
      lic.large = true
      content = content.substring(0,500000) + content.substring(content.length-500000,content.length)

    for l in licences
      if l.domain is '*' or not l.domain or not url? or l.domain.toLowerCase().indexOf(url.toLowerCase().replace('http://','').replace('https://','').replace('www.','').split('/')[0]) isnt -1
        match = l.match.toLowerCase().replace(/[^a-z0-9]/g, '')
        urlmatcher = if l.match.indexOf('://') isnt -1 then l.match.toLowerCase().split('://')[1].split('"')[0].split(' ')[0] else false
        urlmatch = if urlmatcher then content.toLowerCase().indexOf(urlmatcher) isnt -1 else false
        if urlmatch or content.toLowerCase().replace(/[^a-z0-9]/g,'').indexOf(match) isnt -1
          lic.licence = l.licence
          lic.match = l.match
          lic.matched = if urlmatch then urlmatcher else match
          break
  return lic

