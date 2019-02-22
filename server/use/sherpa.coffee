

# docs http://www.sherpa.ac.uk/romeo/apimanual.php?la=en&fIDnum=|&mode=simple
# has an api key set in settings and should be appended as query param "ak"

# A romeo query for an issn is what is immediately required:
# http://www.sherpa.ac.uk/romeo/api29.php?issn=1444-1586

# returns an object in which <romeoapi version="2.9.9"><journals><journal> confirms the journal
# and <romeoapi version="2.9.9"><publishers><publisher><romeocolour> gives the romeo colour
# (interestingly Elsevier is green...)

import moment from 'moment'
import fs from 'fs'


sherpa_romeo = new API.collection {index:"sherpa",type:"romeo"}

API.use ?= {}
API.use.sherpa = {romeo:{}}

# searches the actual romeo API, and if find then if found, saves it to local sherpa_romeo index
# the local index can be populated using routes below, and the local index can be searched using the route below without /search
API.add 'use/sherpa/romeo/search', 
  get: () -> 
    xml = false
    format = true
    if this.queryParams.xml?
      xml = true
      delete this.queryParams.xml
    if this.queryParams.format?
      format = false
      delete this.queryParams.format
    if xml
      this.response.writeHead(200, {'Content-type': 'text/xml; charset=UTF-8', 'Content-Encoding': 'UTF-8'})
      this.response.end API.use.sherpa.romeo.search this.queryParams, xml
    else
      return API.use.sherpa.romeo.search this.queryParams, xml, format

API.add 'use/sherpa/romeo/find', get: () -> return API.use.sherpa.romeo.find this.queryParams

API.add 'use/sherpa/romeo/issn/:issn', get: () -> return API.use.sherpa.romeo.search {issn:this.urlParams.issn}

API.add 'use/sherpa/romeo/colour/:issn', get: () -> return API.use.sherpa.romeo.colour this.urlParams.issn

API.add 'use/sherpa/romeo/updated', get: () -> return API.use.sherpa.romeo.updated()

API.add 'use/sherpa/romeo/download', 
  get: 
    roleRequired:'root'
    action: () -> 
      return API.use.sherpa.romeo.download(this.queryParams.local)

API.add 'use/sherpa/romeo/download.csv', 
  get: 
    roleRequired:'root'
    action: () -> 
      API.convert.json2csv2response(this,API.use.sherpa.romeo.download(this.queryParams.disk).data)

API.add 'use/sherpa/romeo/index', 
  get: 
    roleRequired:'root'
    action: () -> 
      res = API.use.sherpa.romeo.index (if this.queryParams.update? then true else undefined), (if this.queryParams.local? then false else undefined)
      API.mail.send {to: 'alert@cottagelabs.com', subject: 'Sherpa Romeo index complete', text: 'Done'}
      return res
  delete:
    roleRequired:'root'
    action: () -> 
      sherpa_romeo.remove('*') if sherpa_romeo.count() isnt 0
      return true

# INFO: sherpa romeo is one dataset, and fact and ref are built from it. Opendoar is the repo directory, a separate dataset
API.add 'use/sherpa/romeo', () -> return sherpa_romeo.search this



API.use.sherpa.romeo.search = (params,xml=false,format=true) ->
  if params.title?
    params.jtitle = params.title
    delete params.title
  apikey = API.settings.use?.romeo?.apikey
  return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
  url = 'http://www.sherpa.ac.uk/romeo/api29.php?ak=' + apikey + '&'
  url += q + '=' + params[q] + '&' for q of params
  API.log 'Using sherpa romeo for ' + url
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      if xml
        return res.content
      else
        result = API.convert.xml2json res.content
        if format
          return API.use.sherpa.romeo.format {journals: result.romeoapi.journals, publishers: result.romeoapi.publishers}
        else
          return {journals: result.romeoapi.journals, publishers: result.romeoapi.publishers}
    else
      return { status: 'error', data: result}
  catch err
    return { status: 'error', error: err}

API.use.sherpa.romeo.find = (q) ->
  found = sherpa_romeo.find q
  if not found
    rem = API.use.sherpa.romeo.search q
    if rem? and typeof rem is 'object' and rem.status isnt 'error'
      sherpa_romeo.insert rem
      found = rem
  return found

API.use.sherpa.romeo.colour = (issn) ->
  if rec = sherpa_romeo.find({issn: issn}) and rec.publisher?.colour?
    return rec.publisher.colour
  else
    resp = API.use.sherpa.romeo.search {issn:issn}
    try
      return resp.publishers[0].publisher[0].romeocolour[0]
    catch err
      return { status: 'error', data: resp, error: err}

API.use.sherpa.romeo.updated = () ->
  apikey = API.settings.use?.romeo?.apikey
  return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
  url = 'http://www.sherpa.ac.uk/downloads/download-dates.php?ak=' + apikey
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      result = API.convert.xml2json res.content
      ret = 
        publishers:
          added: result['download-dates'].publisherspolicies[0].latestaddition[0]
          updated: result['download-dates'].publisherspolicies[0].latestupdate[0]
        journals:
          added: result['download-dates'].journals[0].latestaddition[0]
          updated: result['download-dates'].journals[0].latestupdate[0]
      ret.latest = if moment(ret.publishers.added).valueOf() > moment(ret.publishers.updated).valueOf() then ret.publishers.added else ret.publishers.updated
      ret.latest = if moment(ret.latest).valueOf() > moment(ret.journals.added).valueOf() then ret.latest else ret.journals.added
      ret.latest = if moment(ret.latest).valueOf() > moment(ret.journals.updated).valueOf() then ret.latest else ret.journals.updated
      try ret.last = sherpa_romeo.find('*', true).created_date
      ret.new = not ret.last? or moment(ret.latest).valueOf() > moment(ret.last,'YYYY-MM-DD HHmm.ss').valueOf()
      return ret
    else
      return { status: 'error', data: result}
  catch err
    return { status: 'error', error: err}

API.use.sherpa.romeo.format = (res, romeoID) ->
  rec = {journal:{},publisher:{}}
  rec.romeoID = romeoID if romeoID
  if res.journals? and res.journals.length and res.journals[0].journal? and res.journals[0].journal.length
    for j of res.journals[0].journal[0]
      rec.journal[j] = res.journals[0].journal[0][j][0] if res.journals[0].journal[0][j].length and res.journals[0].journal[0][j][0]
    rec.journal.title = rec.journal.jtitle if rec.journal.jtitle? and not rec.journal.title?
  if res.publishers? and res.publishers.length and res.publishers[0].publisher? and res.publishers[0].publisher.length
    publisher = res.publishers[0].publisher[0]
    for p of publisher
      if p is '$'
        rec.publisher.sherpa_id = publisher[p].id
        rec.publisher.sherpa_parent_id = publisher[p].parentid
      else if p in ['preprints','postprints','pdfversion']
        if publisher[p].length
          rec.publisher[p] = {}
          for ps of publisher[p][0]
            if publisher[p][0][ps].length
              if publisher[p][0][ps].length > 1
                rec.publisher[p][ps] = []
                for psr of publisher[p][0][ps]
                  rec.publisher[p][ps].push(publisher[p][0][ps][psr].replace(/<.*?>/g,'')) if typeof publisher[p][0][ps][psr] is 'string' and publisher[p][0][ps][psr].replace(/<.*?>/g,'')
              else
                rec.publisher[p][ps] = publisher[p][0][ps][0].replace(/<.*?>/g,'') if typeof publisher[p][0][ps][0] is 'string' and publisher[p][0][ps][0].replace(/<.*?>/g,'')
                rec.publisher[p][ps] = [] if not rec.publisher[p][ps]? and ps.indexOf('restrictions') isnt -1
            else if ps.indexOf('restrictions') isnt -1
              rec.publisher[p][ps] = []
      else if p is 'conditions' and publisher[p].length and typeof publisher[p][0] is 'object' and publisher[p][0].condition? and publisher[p][0].condition.length
        rec.publisher.conditions = []
        for c in publisher[p][0].condition
          rec.publisher.conditions.push(c.replace(/<.*?>/g,'')) if typeof c is 'string' and c.replace(/<.*?>/g,'')
      else if p is 'mandates' and publisher[p].length
        rec.publisher.mandates = []
        if typeof publisher[p][0] is 'string'
          for pm in publisher[p]
            rec.publisher.mandates.push(pm) if pm
        else if typeof publisher[p][0] is 'object' and publisher[p][0].mandate? and publisher[p][0].mandate.length
          for pm in publisher[p][0].mandate
            rec.publisher.mandates.push(pm) if pm
      else if p is 'paidaccess'
        for pm of publisher[p][0]
          rec.publisher[pm] = publisher[p][0][pm][0] if publisher[p][0][pm].length and publisher[p][0][pm][0]
      else if p is 'copyrightlinks'
        if publisher[p][0].copyrightlink
          rec.publisher.copyright = []
          for pc of publisher[p][0].copyrightlink
            rec.publisher.copyright.push {url: publisher[p][0].copyrightlink[pc].copyrightlinkurl[0], text: publisher[p][0].copyrightlink[pc].copyrightlinktext[0]}
      else if p is 'romeocolour'
        rec.publisher.colour = publisher[p][0]
        rec.colour = rec.publisher.colour
        rec.color = rec.colour
      else if p in ['dateadded','dateupdated']
        rec.publisher['sherpa_' + p.replace('date','') + '_date'] = publisher[p][0] #.replace(':','').replace(':','.')
      else
        rec.publisher[p] = publisher[p][0]
        rec.publisher.url = rec.publisher[p] if p is 'homeurl'
  return rec

API.use.sherpa.romeo.download = (local=true) ->
  apikey = API.settings.use?.romeo?.apikey
  return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
  updated = API.use.sherpa.romeo.updated()
  localcopy = '.sherpa_romeo_data.csv'
  if fs.existsSync(localcopy) and local and moment(updated.latest).valueOf() < fs.statSync(localcopy).mtime
    try
      local = JSON.parse fs.readFileSync localcopy
      if local.length
        return {total: local.length, data: local}
  try
    url = 'http://www.sherpa.ac.uk/downloads/journal-issns.php?format=csv&ak=' + apikey
    res = HTTP.call 'GET', url # gets a list of journal ISSNs
    if res.statusCode is 200
      js = API.convert.csv2json res.content
      #js = js.slice(50,70)
      issns = [] # we seem to get dups from the sherpa lists...
      dups = []
      data = []
      for r in js
        try
          issn = r.ISSN.trim().replace(' ','-')
          if issn not in issns
            res = API.use.sherpa.romeo.search {issn:issn}
            try res.journal?.issn ?= issn # some ISSNs in the sherpa download never resolve to anything, so store an empty record with just the ISSN
            try res.romeoID = r['RoMEO Record ID']
            data.push res
            issns.push res.journal.issn
          else
            dups.push issn
      fs.writeFileSync localcopy, JSON.stringify(data,"",2)
      API.mail.send {to: 'alert@cottagelabs.com', subject: 'Sherpa Romeo download complete', text: 'Done, with ' + data.length + ' records and ' + dups.length + ' duplicates'}
      return { total: data.length, duplicates: dups.length, data: data}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', error: err}

API.use.sherpa.romeo.index = (update=API.use.sherpa.romeo.updated().new,local) ->
  if update
    sherpa_romeo.remove('*') if sherpa_romeo.count() isnt 0
    try
      return sherpa_romeo.import API.use.sherpa.romeo.download(local).data
    catch err
      return {status: 'error', err: err}
  else
    return 'Already up to date'



API.use.sherpa.test = (verbose) ->
  console.log('Starting sherpa test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.sherpa = API.use.sherpa.romeo.search {issn: '1748-4995'}
      return _.isEqual result.sherpa, API.use.sherpa.test._examples.record
    () ->
      result.colour = API.use.sherpa.romeo.colour '1748-4995'
      return result.colour is 'green'
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending sherpa test') if API.settings.dev

  return result

API.use.sherpa.test._examples = {
  record: {
    "journals": [
      {
        "journal": [
          {
            "jtitle": [
              "Annals of Actuarial Science"
            ],
            "issn": [
              "1748-4995"
            ],
            "zetocpub": [
              "Cambridge University Press (CUP): PDF Allowed SR / Cambridge University Press (CUP)"
            ],
            "romeopub": [
              "Cambridge University Press (CUP)"
            ]
          }
        ]
      }
    ],
    "publishers": [
      {
        "publisher": [
          {
            "$": {
              "id": "27"
            },
            "name": [
              "Cambridge University Press"
            ],
            "alias": [
              "CUP"
            ],
            "homeurl": [
              "http://www.cambridge.org/uk/"
            ],
            "preprints": [
              {
                "prearchiving": [
                  "can"
                ],
                "prerestrictions": [
                  ""
                ]
              }
            ],
            "postprints": [
              {
                "postarchiving": [
                  "can"
                ],
                "postrestrictions": [
                  ""
                ]
              }
            ],
            "pdfversion": [
              {
                "pdfarchiving": [
                  "cannot"
                ],
                "pdfrestrictions": [
                  ""
                ]
              }
            ],
            "conditions": [
              {
                "condition": [
                  "Author's Pre-print on author's personal website, departmental website, social media websites, institutional repository, non-commercial subject-based repositories, such as PubMed Central, Europe PMC or arXiv",
                  "Author's post-print for HSS journals, on author's personal website, departmental website, institutional repository, non-commercial subject-based repositories, such as PubMed Central, Europe PMC or arXiv, on acceptance of publication",
                  "Author's post-print for STM journals, on author's personal website on acceptance of publication",
                  "Author's post-print for STM journals, on departmental website, institutional repository, non-commercial subject-based repositories, such as PubMed Central, Europe PMC or arXiv, after a <num>6</num> <period units=\"month\">months</period> embargo",
                  "Publisher's version/PDF cannot be used",
                  "Published abstract may be deposited",
                  "Pre-print to record acceptance for publication",
                  "Publisher copyright and source must be acknowledged",
                  "Must link to publisher version or journal website",
                  "Publisher last reviewed on 07/10/2014"
                ]
              }
            ],
            "mandates": [
              ""
            ],
            "paidaccess": [
              {
                "paidaccessurl": [
                  "http://journals.cambridge.org/action/displaySpecialPage?pageId=4576"
                ],
                "paidaccessname": [
                  "Cambridge Open"
                ],
                "paidaccessnotes": [
                  "A paid open access option is available for this journal."
                ]
              }
            ],
            "copyrightlinks": [
              {
                "copyrightlink": [
                  {
                    "copyrightlinktext": [
                      "Open Access Options"
                    ],
                    "copyrightlinkurl": [
                      "http://journals.cambridge.org/action/displaySpecialPage?pageId=4608"
                    ]
                  }
                ]
              }
            ],
            "romeocolour": [
              "green"
            ],
            "dateadded": [
              "2004-01-10 00:00:00"
            ],
            "dateupdated": [
              "2014-10-07 15:16:19"
            ]
          }
        ]
      }
    ]
  }
}