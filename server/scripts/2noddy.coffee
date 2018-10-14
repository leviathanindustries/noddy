
_oab_requests_sherpa = (res) ->
  res._scripts ?= {}
  res._scripts.sherpa ?= []
  processed = {when: Date.now()}
  if not res.sherpa?.color? and not res.journal and (res.url or res.doi)
    processed.nocolour = true
    if not res.doi and res.url and res.url.indexOf('10.') isnt -1
      processed.nodoibuturl = true
      chk = '10.' + res.url.split('10.')[1]
      if chk.indexOf('/') isnt -1
        chk = chk.replace('/','______').split('/')[0].replace('______','/')
        if chk.indexOf('10.') is 0 and chk.indexOf('/') isnt -1 and chk.split('/').length > 1 and chk.split('/')[1].length
          res.doi = chk
    if res.doi
      processed.crossref = true
      try
        cr = API.use.crossref.works.doi res.doi
        if cr
          res.journal = cr['container-title']?[0]
          res.title ?= cr.title?[0]
          res.author ?= cr.author
          res.issn ?= cr.ISSN?[0]
          res.subject ?= cr.subject
          res.publisher ?= cr.publisher
    if not res.journal and not res.doi and res.url and res.url.indexOf('http') is 0
      processed.scrape = true
      try
        meta = API.service.oab.scrape res.url
        if meta
          res.journal ?= meta.journal
          res.keywords ?= meta.keywords
          res.title ?= meta.title
          res.doi ?= meta.doi
          res.email ?= meta.email
          res.author ?= meta.author
          res.issn ?= meta.issn
          res.publisher ?= meta.publisher
  if res.journal and not res.sherpa?.color?
    processed.sherpa = true
    try
      sherpa = API.use.sherpa.romeo.search {jtitle: res.journal}
      res.sherpa = {color:sherpa.publishers[0].publisher[0].romeocolour[0]}
  processed.found = res.sherpa?.color?
  res._scripts.sherpa.push processed
  return res


API.add 'scripts/2noddy/catchup',
  get:
    authRequired: 'root'
    action: () ->
      newusers = API.es.call 'GET', '/clapi/accounts/_search?q=createdAt:>1521086044035&size=10000', undefined, undefined, undefined, undefined, undefined, undefined, false
      for u in newusers.hits.hits
        rec = u._source
        API.es.call 'POST', '/noddy/users/' + rec._id, rec, undefined, undefined, undefined, undefined, undefined, false
      #newoab = API.es.call 'GET', '/oab/request/_search?q=createdAt:>1520248232218&size=10000', undefined, undefined, undefined, undefined, undefined, undefined, false
      #for u in newoab.hits.hits
      #  rec = _oab_requests_sherpa u._source
      #  API.es.call 'POST', '/oab/request/' + rec._id, rec, undefined, undefined, undefined, undefined, undefined, false
      return {users: newusers.hits.total} #, requests: newoab.data.hits.total}

API.add 'scripts/2noddy/accounts',
  get:
    authRequired: 'root'
    action: () ->
      # clapi/accounts -> noddy/accounts
      #API.es.reindex 'clapi', 'accounts', API.es._mapping, 'noddy/users', false
      #API.log {msg:'Scripting accounts from clapi into noddy complete', level:'info', notify:true}
      #return true
      return false

API.add 'scripts/2noddy/bebejam',
  get:
    authRequired: 'root'
    action: () ->
      # noddy_dev/bebejam_* (copy the bebejam types to live noddy) (or separate bebejam, lantern, and other services into their own indexes?)
      #for tp in API.es.types 'noddy_dev'
      #  if tp.indexOf('bebejam_') isnt -1
      #    API.es.reindex 'noddy_dev', tp, API.es._mapping, 'bebejam/' + tp.replace('bebejam_','')
      #API.log {msg:'Scripting dev bebejam into its own index for noddy complete', level:'info', notify:true}
      #return true
      return false

API.add 'scripts/2noddy/oab',
  get:
    authRequired: 'root'
    action: () ->
      # reprocess oab_request
      #API.es.reindex 'oab', 'request', API.es._mapping, undefined, false, _oab_requests_sherpa

      # oab_support is the same format so does not need reprocessing, but will need reindexing anyway to match new mapping
      #API.es.reindex 'oab', 'support'
      API.es.reindex 'oab', 'availability'

      API.log {msg:'Scripting oab from oab into oab, but udpated and mapped for noddy, complete', level:'info', notify:true}
      return true

      # wipe history and availability, the oab index folder has been backed up
      # add a note to stats page of how many availabilities we had before our update
      # (7243384) (1114919 without gsot.gbv.de) (from 27/10/2016 to 05/03/2018)

      # check file store capability for oabutton author request file upload

      # keep indexes that have other use
      # phd, postcode, schools, romeo, fact, devopendoar (although may just rebuild opendoar and delete the dev one at some point)

      # delete unnecessary indexes
      # devbebejam, devclapi, clapi, devoab

      # enable daily off-site backups of critical live indexes
      # oab/request, oab/support, noddy/accounts, bebejam/event, bebejam/comment, bebejam/searches, lantern?, jobs?
      # do we need any old lantern / jobs? or can we expect people just to rerun again?

      # combine phd and leviathan industries and leviathan app sites into one. Combine with CL info


