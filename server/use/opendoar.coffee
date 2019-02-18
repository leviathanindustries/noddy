

# docs:
# http://opendoar.org/tools/api.html
# http://opendoar.org/tools/api13manual.html
# example:
# http://opendoar.org/api13.php?fields=rname&kwd=Aberdeen%20University%20Research%20Archive

opendoar_record = new API.collection {index:"opendoar",type:"record"}

API.use ?= {}
API.use.opendoar = {}

API.add 'use/opendoar/search',
  get: () -> return API.use.opendoar.search this.queryParams.q,this.queryParams.show,this.queryParams.raw

API.add 'use/opendoar/search/:qry',
  get: () -> return API.use.opendoar.search this.urlParams.qry,this.queryParams.show,this.queryParams.raw

API.add 'use/opendoar/download', 
  get: 
    roleRequired:'root'
    action: () -> 
      return API.use.opendoar.download()

API.add 'use/opendoar/download.csv', 
  get: 
    roleRequired:'root'
    action: () -> 
      API.convert.json2csv2response(this,API.use.opendoar.download().data)

API.add 'use/opendoar/index',
  get:
    roleRequired: 'root'
    action: () ->
      res = API.use.opendoar.index()
      API.mail.send {to: 'alert@cottagelabs.com', subject: 'Opendoar index complete', text: 'Done'}
      return res

API.add 'use/opendoar', () -> return opendoar_record.search this



API.use.opendoar.parse = (rec) ->
  ret = {_id: rec.$.rID}
  ret.name = rec.rName?[0]
  ret.acronym = rec.rAcronym?[0]
  ret.url = rec.rUrl?[0]
  ret.oai = rec.rOaiBaseUrl?[0]
  ret.uname = rec.uName?[0]
  ret.uacronym = rec.uAcronym?[0]
  ret.uurl = rec.uUrl?[0]
  ret.oname = rec.oName?[0]
  ret.oacronym = rec.oAcronym?[0]
  ret.ourl = rec.oUrl?[0]
  ret.address = rec.rPostalAddress?[0]
  ret.phone = rec.paPhone?[0]
  ret.fax = rec.paFax?[0]
  ret.description = rec.rDescription?[0]
  ret.remarks = rec.rRemarks?[0]
  ret.established = rec.rYearEstablished[0] if rec.rYearEstablished?[0]?.length > 0 and parseInt(rec.rYearEstablished[0])
  ret.type = rec.repositoryType?[0]
  ret.operational = rec.operationalStatus?[0]
  ret.software = rec.rSoftWareName?[0]
  ret.version = rec.rSoftWareVersion?[0]
  ret.location = {geo:{lat:rec.paLatitude[0],lon:rec.paLongitude[0]}} if rec.paLatitude and rec.paLongitude
  if rec.country?[0]?.cCountry?
    ret.country = rec.country[0].cCountry[0]
    ret.countryIso ?= rec.country[0].cIsoCode?[0]
  if rec.classes?[0]?.class?
    ret.classes = []
    for c in rec.classes[0].class
      cl = {}
      cl.code = c.clCode?[0]
      cl.title = c.clTitle?[0]
      ret.classes.push cl
  if rec.languages?[0]?.language?
    ret.languages = []
    for l in rec.languages[0].language
      ll = {}
      ll.iso = l.lIsoCode?[0]
      ll.name = l.lName?[0]
      ret.languages.push ll
  if rec.contentTypes?[0]?.contentType?
    ret.contents = []
    for t in rec.contentTypes[0].contentType
      co = {}
      co.type = t._
      co.id = t.$?.ctID
      ret.contents.push co
  if rec.policies?[0]?.policy
    ret.policies = []
    for p in rec.policies[0].policy
      po = {}
      po.type = p.policyType?[0]?._
      po.grade = p.policyGrade?[0]?._
      if p.poStandard?[0]?.item?
        std = []
        std.push(st) if typeof st is "string" for st in p.poStandard[0].item
        po.standard = std
      ret.policies.push po
  if rec.contacts?[0]?.person?
    ret.contacts = []
    for cn in rec.contacts[0].person
      cont = {}
      cont.name = cn.pName?[0]
      cont.title = cn.pJobTitle?[0]
      cont.email = cn.pEmail?[0]
      cont.phone = cn.pPhone?[0]
      ret.contacts.push cont
  return ret

API.use.opendoar.search = (qrystr,show='basic',raw) ->
  url = 'http://opendoar.org/api13.php?show=' + show + '&kwd=' + qrystr
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      js = API.convert.xml2json res.content
      data = []
      data.push(if raw then r else API.use.opendoar.parse(r)) for r in js.OpenDOAR.repositories[0].repository
      return { total: js.OpenDOAR.repositories[0].repository.length, data: data}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', error: err}

API.use.opendoar.download = (show='max') ->
  url = 'http://opendoar.org/api13.php?all=y&show=' + show
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      js = API.convert.xml2json res.content
      data = []
      data.push(API.use.opendoar.parse(r)) for r in js.OpenDOAR.repositories[0].repository
      return { total: js.OpenDOAR.repositories[0].repository.length, data: data}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', error: err}

API.use.opendoar.index = () ->
  opendoar_record.remove '*'
  return opendoar_record.import API.use.opendoar.download().data




API.use.opendoar.test = (verbose) ->
  console.log('Starting opendoar test') if API.settings.dev

  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.opendoar = API.use.opendoar.search 'spiral'
      return _.isEqual result.opendoar?.data[0], API.use.opendoar.test._examples.record
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  console.log('Ending opendoar test') if API.settings.dev

  return result

API.use.opendoar.test._examples = {
  record: {
    "_id": "1032",
    "name": "Spiral - Imperial College Digital Repository",
    "acronym": "",
    "url": "https://spiral.imperial.ac.uk/",
    "oai": "https://spiral.imperial.ac.uk/dspace-oai/request",
    "uname": "",
    "uacronym": "",
    "uurl": "",
    "oname": "Imperial College London",
    "oacronym": "",
    "ourl": "https://www.imperial.ac.uk/",
    "phone": "020-75895111",
    "fax": "",
    "description": "College repository providing open access to the research output of the institution.",
    "remarks": "Partners: SHERPA, LEAP Consortium",
    "location": {
      "geo": {
        "lat": "51.488000",
        "lon": "-0.172000"
      }
    },
    "country": "United Kingdom",
    "countryIso": "GB"
  }
}