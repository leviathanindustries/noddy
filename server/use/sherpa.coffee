

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

API.add 'use/sherpa/romeo/search', get: () -> return API.use.sherpa.romeo.search this.queryParams

API.add 'use/sherpa/romeo/colour/:issn', get: () -> return API.use.sherpa.romeo.colour this.urlParams.issn

API.add 'use/sherpa/romeo/updated', get: () -> return API.use.sherpa.romeo.updated()

API.add 'use/sherpa/romeo/download', 
  get: 
    roleRequired:'root'
    action: () -> 
      return API.use.sherpa.romeo.download(this.queryParams.disk)

API.add 'use/sherpa/romeo/download.csv', 
  get: 
    roleRequired:'root'
    action: () -> 
      API.convert.json2csv2response(this,API.use.sherpa.romeo.download(this.queryParams.disk).data)

API.add 'use/sherpa/romeo/index', 
  get: 
    roleRequired:'root'
    action: () -> 
      res = API.use.sherpa.romeo.index()
      API.mail.send {to: 'alert@cottagelabs.com', subject: 'Sherpa Romeo index complete', text: 'Done'}
      return res

API.add 'use/sherpa/romeo', { get: (() -> return sherpa_romeo.search(this.queryParams)), post: (() -> return sherpa_romeo.search(this.bodyParams)) }
API.add 'use/sherpa/romeo.csv', { get: (() -> API.convert.json2csv2response(this, sherpa_romeo.search(this.queryParams ? this.bodyParams))), post: (() -> API.convert.json2csv2response(this, sherpa_romeo.search(this.queryParams ? this.bodyParams))) }
# INFO: sherpa romeo is one dataset, and fact and ref are built from it. Opendoar is the repo directory, a separate dataset



API.use.sherpa.romeo.search = (params) ->
  apikey = API.settings.use?.romeo?.apikey
  return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
  url = 'http://www.sherpa.ac.uk/romeo/api29.php?ak=' + apikey + '&'
  url += q + '=' + params[q] + '&' for q of params
  API.log 'Using sherpa romeo for ' + url
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      result = API.convert.xml2json undefined, res.content
      return {journals: result.romeoapi.journals, publishers: result.romeoapi.publishers}
    else
      return { status: 'error', data: result}
  catch err
    return { status: 'error', error: err}

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
      result = API.convert.xml2json undefined, res.content
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
  rec.sherpa_id = romeoID if romeoID
  for j of res.journals[0].journal[0]
    rec.journal[j] = res.journals[0].journal[0][j]
  for p of res.publishers[0].publisher[0]
    if p is '$'
      rec.publisher.sherpa_id = res.publishers[0].publisher[0][p].id
    else if p in ['preprints','postprints','pdfversion']
      for ps of res.publishers[0].publisher[0][p][0]
        if ps.indexOf('restrictions') isnt -1
          rec.publisher[ps] = []
          for psr in res.publishers[0].publisher[0][p][0][ps]
            psrn = ps.replace('restrictions','restriction')
            rec.publishers[ps].push(psr[psrn][0].replace(/\<.*?\>/g,'')) if psr[psrn]? and psr[psrn].length and psr[psrn][0].length
        else
          rec.publisher[ps] = res.publishers[0].publisher[0][p][ps] if res.publishers[0].publisher[0][p][ps]
    else if p is 'conditions'
      rec.publisher.conditions = res.publishers[0].publisher[0].conditions[0].condition
    else if p is 'mandates'
      rec.publisher.mandates = []
      for pm in res.publishers[0].publisher[0].mandates
        rec.publisher.mandates.push(pm) if pm
    else if p is 'paidaccess'
      for pm of res.publishers[0].publisher[0].paidaccess[0]
        rec.publisher[pm] = res.publishers[0].publisher[0].paidaccess[0][pm][0] if res.publishers[0].publisher[0].paidaccess[0][pm].length and res.publishers[0].publisher[0].paidaccess[0][pm][0]
    else if p is 'copyrightlinks'
      for pc of res.publishers[0].publisher[0][p][0].copyrightlink[0]
        rec.publisher[pc] = res.publishers[0].publisher[0][p][0].copyrightlink[0][pc][0]
    else if p is 'romeocolour'
      rec.publisher.colour = res.publishers[0].publisher[0][p][0]
    else
      rec.publisher[p] = res.publishers[0].publisher[0][p][0]
  return rec

API.use.sherpa.romeo.download = (disk=false) ->
  apikey = API.settings.use?.romeo?.apikey
  return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
  updated = API.use.sherpa.romeo.updated()
  localcopy = '.sherpa_romeo_data.csv'
  if fs.existsSync(localcopy) and (disk or moment(updated.latest).valueOf() < fs.statSync(localcopy).mtime)
    try
      local = JSON.parse fs.readFileSync localcopy
      if local.length
        return {total: local.length, data: local}
  try
    url = 'http://www.sherpa.ac.uk/downloads/journal-issns.php?format=csv&ak=' + apikey
    res = HTTP.call 'GET', url # gets a list of journal ISSNs
    if res.statusCode is 200
      js = API.convert.csv2json undefined, res.content
      js = js.slice(0,50)
      data = []
      for r in js
        #try
        res = API.use.sherpa.romeo.search {issn:r.ISSN.trim().replace(' ','-')}
        data.push API.use.sherpa.romeo.format res, r['RoMEO Record ID']
      fs.writeFileSync localcopy, JSON.stringify(data,"",2)
      API.mail.send {to: 'alert@cottagelabs.com', subject: 'Sherpa Romeo download complete', text: 'Done'}
      return { total: data.length, data: data}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', error: err}

API.use.sherpa.romeo.index = () ->
  update = true
  try update = API.use.sherpa.romeo.updated().new isnt true
  if update
    sherpa_romeo.remove('*') if sherpa_romeo.count() isnt 0
    return sherpa_romeo.import API.use.sherpa.romeo.download().data
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