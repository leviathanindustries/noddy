
API.use ?= {}

API.add 'use/chemicaltagger', 
  get: () -> 
    return API.use.chemicaltagger this.queryParams.q, not this.queryParams.simplify?
  post: () -> 
    return API.use.chemicaltagger this.request.body, not this.queryParams.simplify?

API.use.chemicaltagger = (content, opts={}) ->
  opts.simplify ?= true
  opts.types ?= ['NounPhrase','ActionPhrase']
  opts.types = opts.types.split(',') if typeof opts.types is 'string'
  if opts.cache isnt false
    checksum = API.job.sign content, opts
    exists = API.http.cache checksum, 'chemicaltagger'
    return exists if exists
  
  res = HTTP.call 'POST', 'http://chemicaltagger.ch.cam.ac.uk/submit', {params: {ChemistryType: 'Organic', body: content}}
  rec = API.convert.xml2json API.http.decode res.content.split('<textarea')[1].split('>')[1].split('</textarea')[0]
  if opts.simplify
    recs = []
    if rec?.Document?.Sentence?
      for c in rec.Document.Sentence
        for nk in opts.types
          if nk is 'ActionPhrase'
            ac = {'NounPhrase': []}
            try
              for ap in c[nk]
                for apn in (if _.isArray(ap.NounPhrase) then ap.NounPhrase else [ap.NounPhrase])
                  ac.NounPhrase.push apn
            c = ac
            nk = 'NounPhrase'
          for cc in (if _.isArray(c[nk]) then c[nk] else [c[nk]])
            if cc
              for cm in (if _.isArray(cc.NN) then cc.NN else [cc.NN])
                if cm
                  cm = cm.replace('#','')
                  recs.push(cm) if cm and recs.indexOf(cm) is -1
              for ecm in (if _.isArray(cc.MOLECULE) then cc.MOLECULE else [cc.MOLECULE])
                if typeof ecm?.OSCARCM?['OSCAR-CM'] is 'string'
                  ecm.OSCARCM['OSCAR-CM'] = ecm.OSCARCM['OSCAR-CM'].replace('#','')
                  recs.push(ecm.OSCARCM['OSCAR-CM']) if ecm.OSCARCM['OSCAR-CM'] and recs.indexOf(ecm.OSCARCM['OSCAR-CM']) is -1
    rec = recs

  API.http.cache checksum, 'chemicaltagger', rec
  return rec
  
  


