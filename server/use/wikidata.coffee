
import crypto from 'crypto'

# can build a local wikidata from dumps
# https://dumps.wikimedia.org/wikidatawiki/entities/latest-all.json.gz
# https://www.mediawiki.org/wiki/Wikibase/DataModel/JSON
# it is about 80gb compressed. Each line is a json object so can uncompress and read line by line then load into an index
# then make available all the usual search operations on that index
# then could try to make a way to find all mentions of an item in any block of text
# and make wikidata searches much faster
# downloading to index machine which has biggest disk takes about 5 hours
# there is also a recent changes API where could get last 30 days changes to items to keep things in sync once first load is done
# to bulk load 5000 every 10s would take about 48 hours

# may also be able to get properties by query
# https://www.wikidata.org/w/api.php?action=wbsearchentities&search=doctoral%20advisor&language=en&type=property&format=json
# gets property ID for string, just need to reverse. (Already have a dump accessible below, but for keeping up to date...)

@wikidata_record = new API.collection {index:"wikidata",type:"record"}

API.use ?= {}
API.use.wikidata = {}

API.add 'use/wikidata', 
  get: () -> return API.use.wikidata.search this.queryParams
  post: () -> return API.use.wikidata.search this.bodyParams
API.add 'use/wikidata/:qid', get: () -> return API.use.wikidata.get this.urlParams.qid, this.queryParams.dereference, this.queryParams.update, this.queryParams.snakalyse
API.add 'use/wikidata/find', get: () -> return API.use.wikidata.find this.queryParams.q, this.queryParams.dereference, this.queryParams.update, this.queryParams.snakalyse

API.add 'use/wikidata/properties', get: () -> return API.use.wikidata.properties(this.queryParams.refresh)
API.add 'use/wikidata/properties/generate', get: () -> return API.use.wikidata.properties(true)
API.add 'use/wikidata/properties/:prop', get: () -> return API.use.wikidata.property this.urlParams.prop, this.queryParams.simple
API.add 'use/wikidata/property', get: () -> return API.use.wikidata.property.find this.queryParams.q, this.queryParams.simple
API.add 'use/wikidata/property/:prop', get: () -> return API.use.wikidata.property this.urlParams.prop, this.queryParams.simple
API.add 'use/wikidata/property/:prop/terms', get: () -> return API.use.wikidata.property.terms this.urlParams.prop, this.queryParams.size, this.queryParams.counts, this.queryParams.alphabetical

API.add 'use/wikidata/import', post: () -> return API.use.wikidata.import this.request.body


# routes to remotes
API.add 'use/wikidata/retrieve/:qid', get: () -> return API.use.wikidata.retrieve this.urlParams.qid, this.queryParams.all
API.add 'use/wikidata/simplify', get: () -> return API.use.wikidata.simplify this.queryParams.qid, this.queryParams.q, this.queryParams.url
API.add 'use/wikidata/simplify/:qid', get: () -> return API.use.wikidata.simplify this.urlParams.qid



# direct methods to local copy
API.use.wikidata.search = (params, dereference=false, update=true, snakalyse=false, opts) ->
  if typeof params is 'object'
    for pr in ['dereference','update','snakalyse']
      if params[pr]?
        if pr is 'dereference' then dereference = params[pr] else if pr is 'update' then update = params[pr] else snakalyse = params[pr]
        delete params[pr]
  res = wikidata_record.search params, opts
  if (dereference or snakalyse) and res?.hits?.hits? and res.hits.hits.length and res.hits.hits[0]._source?
    for r of res?.hits?.hits
      res.hits.hits[r]._source = API.use.wikidata.get res.hits.hits[r]._source, dereference, update, snakalyse
  return res

API.use.wikidata.find = (qr, dereference=false, update=true, snakalyse=false, opts={}) ->
  opts.size ?= 1
  recs = API.use.wikidata.search qr, dereference, update, snakalyse, opts
  return if recs?.hits?.hits? and recs.hits.hits.length then recs.hits.hits[0]._source else undefined
    
API.use.wikidata.get = (qid, dereference=false, update=true, snakalyse=false) ->
  qid = wikidata_record.get(qid) if typeof qid isnt 'object'
  if dereference and qid?
    mimes = []
    for m of API.convert._mimes
      mimes.push(m) if m not in mimes and API.convert._mimes[m].indexOf('image') is 0
    u = false
    im = false
    mainimg = false
    for s of qid.snaks
      if qid.snaks[s].property? and qid.snaks[s].qid? and not qid.snaks[s].value?
        if not qid.snaks[s].key?
          key = API.use.wikidata.property qid.snaks[s].property
          if key?
            qid.snaks[s].key = key
            u = true
        v = API.use.wikidata.get qid.snaks[s].qid
        if v?.label?
          qid.snaks[s].value = v.label
          u = true
      if qid.snaks[s].key? and (qid.snaks[s].key in ['image','chemical structure'] or (not mainimg and (qid.snaks[s].key.endsWith(' image') or qid.snaks[s].value and qid.snaks[s].value.indexOf('.') isnt -1)))
        if qid.snaks[s].key is 'image' or (qid.snaks[s].key is 'chemical structure' and not mainimg)
          imageurl = true
          mainimg = true
        else if qid.snaks[s].imgurl
          imageurl = true
        else
          imageurl = false
          vs = qid.snaks[s].value.toLowerCase()
          for n in mimes
            if vs.endsWith n
              imageurl = true
              break
        if imageurl
          if not qid.snaks[s].imgurl
            u = true
          if qid.snaks[s].value.indexOf('http') is 0
            qid.snaks[s].imgurl = qid.snaks[s].value
          else
            iu = 'https://upload.wikimedia.org/wikipedia/commons/'
            img = qid.snaks[s].value.replace(/ /g,'_')
            mds = crypto.createHash('md5').update(img, 'utf8').digest('hex') # base64
            iu += mds.charAt(0) + '/' + mds.charAt(0) + mds.charAt(1) + '/'
            iu += encodeURIComponent img
            qid.snaks[s].imgurl = iu
          if not qid.image or mainimg
            im = qid.snaks[s].imgurl
    upd = {}
    if not qid.wikipedia and qid.sitelinks?.enwiki?.title
      upd.wikipedia = 'https://en.wikipedia.org/wiki/' + qid.sitelinks.enwiki.title.replace(/ /g,'_')
      qid.wikipedia = upd.wikipedia
    if update and (u or im or not _.isEmpty upd) and qid._id?
      upd.snaks = qid.snaks if u
      if im and im isnt qid.image
        upd.image = im
        qid.image = im
      wikidata_record.update qid._id, upd
  if snakalyse
    qid.snakalysed = API.use.wikidata.snakalyse qid
  return qid

_got_props = false
_got_props_when = false
API.use.wikidata.properties = (refresh=604800000) ->
  refresh = 0 if refresh is true
  try refresh = parseInt(refresh) if typeof refresh is 'string'
  refresh = 0 if isNaN refresh or typeof refresh isnt 'number'
  if _got_props_when isnt false and Date.now() - _got_props_when < refresh
    return _got_props
  else
    props = API.http.cache 'generated', 'wikidata_properties', undefined, refresh
    if props?
      _got_props = props
      _got_props_when = Date.now()
      return props
    else
      props = {}
      content = API.http.cache 'wikipage', 'wikidata_properties', undefined, Math.floor(refresh/2)
      if not content?
        res = HTTP.call 'GET', 'https://www.wikidata.org/wiki/Wikidata:Database_reports/List_of_properties/all'
        if res?.content
          API.http.cache 'wikipage', 'wikidata_properties', res.content
          content = res.content
      if content?
        try
          tb = content.split('<table class="wikitable sortable">')[1].split('</table>')[0]
          rows = tb.split '</tr>'
          rows.shift() # the first row is headers
          pids = 0
          for row in rows
            try
              prop = {}
              parts = row.split '</td>'
              try prop.pid = parts[0].replace('</a>','').split('>').pop().trim().replace('\n','')
              try prop.label = parts[1].replace('</a>','').split('>').pop().trim().replace('\n','')
              try prop.desc = parts[2].replace('</a>','').split('>').pop().trim().replace('\n','')
              try prop.alias = parts[3].replace('</a>','').split('>').pop().replace(/, or/g,',').replace(/, /g,',').trim().replace('\n','').split(',')
              try prop.type = parts[4].replace('</a>','').split('>').pop().trim().replace('\n','')
              try prop.count = parts[5].replace('</a>','').split('>').pop().replace(/,/g,'').trim().replace('\n','')
              if typeof prop.pid is 'string' and prop.pid.length and prop.pid.startsWith 'P'
                props[prop.pid] = prop
                pids += 1
          console.log pids
          if not _.isEmpty props
            API.http.cache 'generated', 'wikidata_properties', props
            _got_props = props
            _got_props_when = Date.now()
      return props

API.use.wikidata.property = (prop,simple=true) ->
  res = API.use.wikidata.properties()[prop]
  if res?
    return if simple then res.label else res
  else
    return undefined

API.use.wikidata.property.find = (q,simple=false) ->
  return undefined if not q?
  props = API.use.wikidata.properties()
  q = q.toLowerCase()
  qf = q.split(' ')[0]
  partials = []
  firsts = []
  for p of props
    pls = props[p].label.toLowerCase()
    if pls is q
      return if simple then props[p].pid else props[p]
    else if pls.indexOf(q) isnt -1
      partials.push if simple then props[p].pid else props[p]
    else if pls.indexOf(qf) isnt -1
      firsts.push if simple then props[p].pid else props[p]
  return partials.concat firsts

API.use.wikidata.property.terms = (prop,size=1000,counts=true,alphabetical=false) ->
  terms = {}
  loops = false
  key = false
  max = 0
  lp = 0
  sz = if size < 1000 then size else 1000
  qr = 'snaks.property.exact:' + prop
  while _.keys(terms).length < size and (loops is false or lp < loops)
    console.log _.keys(terms).length, lp, loops
    res = API.use.wikidata.search {q: qr, size: sz, from: sz*lp}
    max = res.hits.total if res?.hits?.total?
    loops = if not res?.hits?.total? then 0 else Math.floor res.hits.total / sz
    for rec in res?.hits?.hits ? []
      for snak in rec._source?.snaks ? []
        if snak.property is prop
          key = snak.key if snak.key? and key is false
          if not snak.value? and snak.qid?
            qv = API.use.wikidata.get snak.qid
            snak.value = qv.label if qv?
          if snak.value?
            if not terms[snak.value]?
              terms[snak.value] = 0
              qr += ' AND NOT snaks.qid.exact:' + snak.qid if snak.qid? and qr.split('AND NOT').length < 100 #what is max amount of NOT terms?
            terms[snak.value] += 1
    lp += 1
  out = []
  out.push({term: t, count: terms[t]}) for t of terms
  if alphabetical
    out = out.sort (a,b) -> if a.term.toLowerCase().replace(/ /g,'') > b.term.toLowerCase().replace(/ /g,'') then 1 else -1
  else
    out = out.sort (a,b) -> if b.count > a.count then 1 else -1
  return if counts then {property: key, total: max, terms: out} else _.pluck(out, 'term')
  
API.use.wikidata.import = (recs) ->
  if _.isArray(recs) and recs.length
    return wikidata_record.insert recs
  else
    return undefined

API.use.wikidata.snakalyse = (snaks) ->
  res = {meta: {}, total: 0, person: 0, orgs: 0, locs: 0, keys: []}
  rec = {}
  if typeof snaks is 'object' and snaks.snaks?
    rec = snaks
    snaks = snaks.snaks 
  return res if not snaks?
  snaks = [snaks] if not _.isArray snaks
  seen = []
  hascountry = false
  hasviaf = false
  hassex = false
  hasfamily = false
  for snak in snaks
    if snak.key
      res.keys.push(snak.key) if snak.key not in res.keys
      res.total += 1
      if snak.key + '_' + snak.value not in seen
        seen.push snak.key + '_' + snak.value
        tsk = snak.key.replace(/ /g,'_')
        hascountry = true if snak.key is 'country'
        hasviaf = true if snak.key is 'VIAF ID'
        hassex = true if snak.key is 'sex or gender'
        hasfamily = true if snak.key is 'family name'

        if tsk.length and (snak.key in _props.research or snak.key in ['MeSH code','MeSH descriptor ID','MeSH term ID','MeSH concept ID',
            'ICD-9-CM','ICD-9','ICD-10','ICD-10-CM',
            'ICTV virus ID','ICTV virus genome composition',
            'IUCN taxon ID','NCBI taxonomy ID'
            'DiseasesDB','GARD rare disease ID',
            "UniProt protein ID","RefSeq protein ID","Ensembl protein ID","Ensembl transcript ID",
            "HGNC gene symbol","Gene Atlas Image","GeneReviews ID",
            "Genetics Home Reference Conditions ID","FAO 2007 genetic resource ID","GeneDB ID","Gene Ontology ID","Ensembl gene ID",
            "Entrez Gene ID","HomoloGene ID",
            "InChIKey","InChI",
            'Dewey Decimal Classification','Library of Congress Classification',
            "AICS Chemical ID","MassBank accession ID",'ChEMBL ID',
            'LiverTox ID'
          ])
          res.meta[tsk] = [] if not _.isArray res.meta[tsk] 
          res.meta[tsk].push {value: snak.value, qid: snak.qid}

        if snak.key in ['AICS Chemical ID','ChEMBL ID','chemical formula','chemical structure',"MassBank accession ID"] or snak.qid in ['Q11173'] # chemical compound
          res.meta.chemical = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('chemical') if 'chemical' not in res.meta.what

        if snak.key in ['ICTV virus ID','ICTV virus genome composition','has natural reservoir'] or snak.key is 'instance of' and snak.value is 'strain'
          res.meta.virus = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('virus') if 'virus' not in res.meta.what

        if snak.key in ['DrugBank ID','significant drug interaction']
          res.meta.drug = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('drug') if 'drug' not in res.meta.what

        if snak.key in ['LiverTox ID','eMedicine ID','medical condition treated','European Medicines Agency product number'] or (snak.key is 'instance of' and snak.qid in ['Q12140','Q35456']) # medication, essential medicine
          res.meta.medicine = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('medicine') if 'medicine' not in res.meta.what

        if snak.key in ['GARD rare disease ID','DiseasesDB','drug used for treatment','symptoms','ICD-9','ICD-10']
          res.meta.disease = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('disease') if 'disease' not in res.meta.what

        if snak.key in ["UniProt protein ID","RefSeq protein ID","Ensembl protein ID"]
          res.meta.protein = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('protein') if 'protein' not in res.meta.what

        if snak.key in ["HGNC gene symbol","Gene Atlas Image","GeneReviews ID","Genetics Home Reference Conditions ID","FAO 2007 genetic resource ID",
            "GeneDB ID","Gene Ontology ID","Ensembl gene ID","Ensembl transcript ID","Entrez Gene ID","HomoloGene ID"]
          res.meta.gene = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('gene') if 'gene' not in res.meta.what

        if snak.key in _props.organisation or (snak.key is 'instance of' and ((typeof snak.value is 'string' and snak.value.toLowerCase().indexOf('company') isnt -1) or snak.qid in ['Q31855'])) # research institute
          res.orgs += 1
          res.meta.organisation = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('organisation') if 'organisation' not in res.meta.what
        else if snak.key in _props.location or (snak.key is 'instance of' and snak.qid in [
          'Q3624078','Q123480','Q170156','Q687554','Q43702','Q206696','Q6256']) # sovereign state, landlocked country, confederation, Federal Treaty, federal state, Helvetic Republic, country
          res.locs += 1
          res.meta.place = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('place') if 'place' not in res.meta.what

        if snak.key is 'CBDB ID' or (snak.key is 'instance of' and snak.qid is 'Q5') # human
          res.person += 1
          res.meta.person = rec.label ? true
          res.meta.what ?= []
          res.meta.what.push('person') if 'person' not in res.meta.what

        if snak.location
          res.meta.location = snak.location

  if hasviaf and hascountry and not res.meta.place? # to try to avoid other things that have country, but things other than places have viaf too - this may not work if people often have viaf and country
    res.locs += 1
    res.meta.place = rec.label ? true
    res.meta.what ?= []
    res.meta.what.push('place') if 'place' not in res.meta.what
  if hassex and hasfamily and not res.meta.person?
    res.person += 1
    res.meta.person = rec.label ? true
    res.meta.what ?= []
    res.meta.what.push('person') if 'person' not in res.meta.what
  if res.meta.what? and 'organisation' in res.meta.what and 'place' in res.meta.what
    delete res.meta.place if res.meta.place?
    res.meta.what = _.without res.meta.what, 'place'
  if res.meta.what? and 'disease' in res.meta.what
    delete res.meta.medicine if res.meta.medicine?
    delete res.meta.drug if res.meta.drug?
    res.meta.what = _.without(res.meta.what, 'medicine') if 'medicine' in res.meta.what
    res.meta.what = _.without(res.meta.what, 'drug') if 'drug' in res.meta.what
  return res


_props = {
  #ORGANISATION
  organisation: [
    "headquarters location",
    "subsidiary",
    "typically sells",
    "Merchant Category Code",
    #"industry",
    "parent organization"
    #"Ringgold ID" - locations have ringgold IDs too :(
  ],

  #LOCATION
  location: [
    "diplomatic relation",
    "M.49 code",
    "capital of",
    "postal code",
    "local dialing code",
    "locator map image",
    "shares border with",
    "coordinate location",
    "located on terrain feature",
    "detail map",
    "located in time zone",
    "continent",
    "lowest point",
    "highest point",
    "location map",
    "relief location map",
    "coordinates of easternmost point",
    "coordinates of westernmost point",
    "coordinates of northernmost point",
    "coordinates of southernmost point",
    "located in the administrative territorial entity",
    "China administrative division code",
    "UIC numerical country code",
    "UIC alphabetical country code",
    "coat of arms image",
    #"country",
    "head of government",
    "GS1 country code",
    "country calling code",
    "language used",
    "currency",
    "capital",
    "office held by head of state",
    "head of state",
    "flag",
    "flag image",
    "official language",
    "contains administrative territorial entity",
    "mobile country code",
    "INSEE countries and foreign territories code"
  ],
  
  #SOURCES
  sources: [
    "Google Knowledge Graph ID",
    "Microsoft Academic ID",
    "BBC Things ID",
    "Getty AAT ID",
    "Quora topic ID",
    
    "image",
    "subreddit",
  
    "PhilPapers topic",
  
    "Wikitribune category",
    "New York Times topic ID",
    "The Independent topic ID",
    "Google News topics ID",
    "IPTC NewsCode",
    "Guardian topic ID",
  
    "Library of Congress Control Number (LCCN) (bibliographic)",
    "Library of Congress Classification",
    "Library of Congress authority ID",
    "LoC and MARC vocabularies ID",
  
    "Encyclopedia of Life ID",
    "Encyclopædia Britannica Online ID",
    "Encyclopædia Universalis ID",
    "Encyclopedia of Modern Ukraine ID",
    "Stanford Encyclopedia of Philosophy ID",
    "Canadian Encyclopedia article ID",
    "Cambridge Encyclopedia of Anthropology ID",
    "Great Aragonese Encyclopedia ID",
    "Orthodox Encyclopedia ID",
    "Treccani's Enciclopedia Italiana ID",
    "Gran Enciclopèdia Catalana ID",
  
    "Danish Bibliometric Research Indicator level",
    "Danish Bibliometric Research Indicator (BFI) SNO/CNO",
    "Biblioteca Nacional de España ID",
    "Finnish national bibliography corporate name ID",
    "Libraries Australia ID",
    "Bibliothèque nationale de France ID",
    "National Library of Brazil ID",
    "Shanghai Library place ID",
    "National Library of Greece ID",
    "Portuguese National Library ID",
    "National Library of Iceland ID",
    "National Library of Israel ID",
    "Open Library ID",
    "Open Library subject ID",
  
    "OpenCitations bibliographic resource ID",
  
    "UNESCO Thesaurus ID",
    "ASC Leiden Thesaurus ID",
    "BNCF Thesaurus ID",
    "NCI Thesaurus ID",
    "STW Thesaurus for Economics ID",
    "Thesaurus For Graphic Materials ID",
    "UK Parliament thesaurus ID",
  
    "Wolfram Language entity type",
    "Wolfram Language unit code",
    "Wolfram Language entity code",
  
    "OmegaWiki Defined Meaning"
  ],

  #RESEARCH
  research: [
    "taxonomic type",
    "taxon name",
    "taxon rank",
    "parent taxon",
    "found in taxon",
    "taxon synonym",
    "this taxon is source of",
    "taxon range map image",
  
    "biological process",
    "ortholog",
    "strand orientation",
    "cytogenetic location",
    "chromosome",
    "genomic start",
    "genomic end",
    "cell component",
    "element symbol",
    "encodes",
    "significant drug interaction",
    "molecular function",
    "possible medical findings",
    "health specialty",
    "chemical formula",
    "chemical structure",
    "physically interacts with",
    "active ingredient in",
    "therapeutic area",
    "afflicts",
    "defining formula",
    "measured by",
    "vaccine for",
    "introduced feature",
    "has contributing factor",
    "has active ingredient",
    "has natural reservoir",
    "anatomical location",
    "development of anatomical structure",
    "medical condition treated",
    "arterial supply",
    "venous drainage",
    "pathogen transmission process",
    "risk factor",
    "possible treatment",
    "drug used for treatment",
    "medical examinations",
    "genetic association",
    "symptoms",
    "encoded by",
    #"location",
    "connects with",
    "property constraint",
    "instance of",
    "subclass of",
    "does not have part",
    "has cause",
    "subject has role",
    "has quality",
    "has part",
    "has effect",
    "has immediate cause",
    "has parts of the class",
    "part of",
    "opposite of",
    "facet of",
    "natural reservoir of",
    "equivalent property",
    "partially coincident with",
    "equivalent class",
    "said to be the same as",
    "properties for this type",
    "used by",
    "Commons category",
    "route of administration"
  ],

  #IDS
  ids: [
    "MeSH code",
    "MeSH descriptor ID",
    "MeSH term ID",
    "MeSH concept ID",
  
    "ICD-9-CM",
    "ICD-9",
    "ICD-10",
    "ICD-10-CM",
    "ICD-11 (foundation)",
  
    "ICTV virus ID",
    "ICTV virus genome composition",
  
    "iNaturalist taxon ID",
    "ADW taxon ID",
    "BioLib taxon ID",
    "Fossilworks taxon ID",
    "IUCN taxon ID",
    "NCBI taxonomy ID",
  
    "NCBI locus tag",
    "IUCN conservation status",
    "Dewey Decimal Classification",
    "DiseasesDB",
    "GeoNames feature code",
    "GeoNames ID",
    "ITU letter code",
    "MSW ID",
    "NBN System Key",
    "EPPO Code",
    "SPLASH",
    "isomeric SMILES",
    "canonical SMILES",
    "InChIKey",
    "InChI",
    "NSC number",
    "Reaxys registry number",
    "European Medicines Agency product number",
    "OCLC control number",
    "CosIng number",
    "Gmelin number",
    "EC enzyme number",
    "ZVG number",
    "MCN code",
    "Kemler code",
    "GenBank Assembly accession",
    "NUTS code",
    "EC number",
    "CAS Registry Number",
    "ATC code",
    "MathWorld identifier",
    "UNSPSC Code",
    "IPA transcription",
    "ISNI",
  
    "ISO 3166-2 code",
    "ISO 4 abbreviation",
    "ISO 3166-1 numeric code",
    "ISO 3166-1 alpha-3 code",
    "ISO 3166-1 alpha-2 code",
    "ITU/ISO/IEC object identifier",
    "U.S. National Archives Identifier",
  
    "IRMNG ID",
    "Global Biodiversity Information Facility ID",
    "Human Phenotype Ontology ID",
    "Freebase ID",
    "YSA ID",
    "PersonalData.IO ID",
    "BabelNet ID",
    "Klexikon article ID",
    "EuroVoc ID",
    "JSTOR topic ID",
    "Semantic Scholar author ID",
    "GND ID",
    "PSH ID",
    "YSO ID",
    "HDS ID",
    "Disease Ontology ID",
    "Elhuyar ZTH ID",
    "MonDO ID",
    "ORCID iD",
    "WorldCat Identities ID",
    "VIAF ID",
    "archINFORM location ID",
    "Pleiades ID",
    "Nomisma ID",
    "GACS ID",
    "NE.se ID",
    "FAST ID",
    "GARD rare disease ID",
    "MedlinePlus ID",
    "Dagens Nyheter topic ID",
    "DMOZ ID",
    "Analysis &amp; Policy Observatory term ID",
    "DR topic ID",
    "ICPC 2 ID",
    "OMIM ID",
    "Store medisinske leksikon ID",
    "NHS Health A to Z ID",
    "Patientplus ID",
    "eMedicine ID",
    "BHL Page ID",
    "Invasive Species Compendium Datasheet ID",
    "OSM relation ID",
    "GeoNLP ID",
    "Zhihu topic ID",
    "Observation.org ID",
    "IUPAC Gold Book ID",
    "Dyntaxa ID",
    "New Zealand Organisms Register ID",
    "Fauna Europaea New ID",
    "Fauna Europaea ID",
    "Belgian Species List ID",
    "TDKIV term ID",
    "Foundational Model of Anatomy ID",
    "UBERON ID",
    "NSK ID",
    "CANTIC ID",
    "NALT ID",
    "WoRMS-ID for taxa",
  
    "Crossref funder ID",
    "RoMEO publisher ID",
    "NORAF ID",
    "GRID ID",
    "CONOR ID",
    "Publons publisher ID",
    "SHARE Catalogue author ID",
    "NUKAT ID",
    "EGAXA ID",
    "ULAN ID",
    "ROR ID",
    "HAL structure ID",
    "ELNET ID",
    "TA98 Latin term",
    "Terminologia Anatomica 98 ID",
    "GPnotebook ID",
    "archINFORM keyword ID",
    "FOIH heritage types ID",
    "ILI ID",
    "Römpp online ID",
    "Pfam ID",
    "ECHA InfoCard ID",
    "MassBank accession ID",
    "ChEBI ID",
    "NDF-RT ID",
    "Guide to Pharmacology Ligand ID",
    "ChEMBL ID",
    "ChemSpider ID",
    "PubChem CID",
    "KEGG ID",
    "DSSTox substance ID",
    "CA PROP 65 ID",
    "IEDB Epitope ID",
    "PDB ligand ID",
    "DrugBank ID",
    "PDB structure ID",
    "LiverTox ID",
    "RxNorm ID",
    "Rosetta Code ID",
    "UniProt journal ID",
    "NLM Unique ID",
    "Scopus Source ID",
    "JUFO ID",
    "Human Metabolome Database ID",
    "NIAID ChemDB ID",
    "KNApSAcK ID",
    "Joconde inscription ID",
    "BIDICAM authority ID",
    "BVPH authority ID",
    "LEM ID",
    "ICSC ID",
    "MinDat mineral ID",
    "AICS Chemical ID",
    "Reactome ID",
    "Xenopus Anatomical Ontology ID",
    "ARKive ID",
    "CITES Species+ ID",
    "UniProt protein ID",
    "RefSeq protein ID",
    "Ensembl protein ID",
    "HGNC gene symbol",
    "Gene Atlas Image",
    "GeneReviews ID",
    "Genetics Home Reference Conditions ID",
    "FAO 2007 genetic resource ID",
    "GeneDB ID",
    "Gene Ontology ID",
    "Ensembl gene ID",
    "Ensembl transcript ID",
    "Entrez Gene ID",
    "HomoloGene ID",
    "Pschyrembel Online ID",
    "HCIS ID",
    "BMRB ID",
    "ZINC ID",
    "HSDB ID",
    "3DMet ID",
    "SpectraBase compound ID",
    "GTAA ID",
    "HGNC ID",
    "RefSeq RNA ID",
    "History of Modern Biomedicine ID",
    "Gynopedia ID",
    "De Agostini ID",
    "ESCO skill ID",
    "ANZSRC FoR ID",
    "Spider Ontology ID",
    "Coflein ID",
    "SAGE journal ID",
    "ERA Journal ID",
    "NIOSHTIC-2 ID",
    "ISOCAT id"
  ]
}



# methods to remote original source
API.use.wikidata.retrieve = (qid,all,matched) ->
  if not all and exists = API.http.cache qid, 'wikidata_retrieve'
    try
      if matched and (not exists.matched? or matched not in exists.matched)
        exists.matched ?= []
        exists.matched.push matched
        if f = API.http._colls.wikidata_retrieve.find 'lookup.exact:"' + qid + '"', true
          API.http._colls.wikidata_retrieve.update f._id, {'_raw_result.content.matched':exists.matched}
    return exists
  try
    u = 'https://www.wikidata.org/wiki/Special:EntityData/' + qid + '.json'
    res = HTTP.call 'GET',u
    r = if all then res.data.entities[qid] else {}
    r.type = res.data.entities[qid].type
    r.qid = res.data.entities[qid].id
    r.label = res.data.entities[qid].labels?.en?.value
    r.matched = [matched] if matched?
    r.description = res.data.entities[qid].descriptions?.en?.value
    r.wikipedia = res.data.entities[qid].sitelinks?.enwiki?.url
    r.wid = res.data.entities[qid].sitelinks?.enwiki?.url?.split('wiki/').pop()
    r.infokeys = []
    r.info = {}
    for c of res.data.entities[qid].claims
      claim = res.data.entities[qid].claims[c]
      wdp = API.use.wikidata.property c
      wdp ?= c
      r.infokeys.push wdp
      #for s in claim, do something...
      r.info[wdp] = claim
    API.http.cache qid, 'wikidata_retrieve', r
    return r
  catch err
    return {}


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
  
API.use.wikidata.simplify = (qid,q,url,drill=true) ->
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
    if drill
      for key in data.infokeys
        try
          dk = API.use.wikidata.drill data.info[key][0].mainsnak.datavalue.value.id
          res[key] = dk if dk
  return res

