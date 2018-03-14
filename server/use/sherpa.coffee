

# docs http://www.sherpa.ac.uk/romeo/apimanual.php?la=en&fIDnum=|&mode=simple
# has an api key set in settings and should be appended as query param "ak"

# A romeo query for an issn is what is immediately required:
# http://www.sherpa.ac.uk/romeo/api29.php?issn=1444-1586

# returns an object in which <romeoapi version="2.9.9"><journals><journal> confirms the journal
# and <romeoapi version="2.9.9"><publishers><publisher><romeocolour> gives the romeo colour
# (interestingly Elsevier is green...)

API.use ?= {}
API.use.sherpa = {romeo:{}}

API.add 'use/sherpa/romeo/search', get: () -> return API.use.sherpa.romeo.search this.queryParams

API.add 'use/sherpa/romeo/colour/:issn', get: () -> return API.use.sherpa.romeo.colour this.urlParams.issn


API.use.sherpa.romeo.search = (params) ->
  apikey = API.settings.use?.romeo?.apikey
  return { status: 'error', data: 'NO ROMEO API KEY PRESENT!'} if not apikey
  url = 'http://www.sherpa.ac.uk/romeo/api29.php?ak=' + apikey + '&'
  url += q + '=' + params[q] + '&' for q of params
  API.log 'Using sherpa romeo for ' + url
  res = HTTP.call 'GET', url
  if res.statusCode is 200
    result = API.convert.xml2json undefined, res.content
    return {journals: result.romeoapi.journals, publishers: result.romeoapi.publishers}
  else
    return { status: 'error', data: result}

API.use.sherpa.romeo.colour = (issn) ->
	resp = API.use.sherpa.romeo.search {issn:issn}
	try
		return resp.publishers[0].publisher[0].romeocolour[0]
	catch err
		return { status: 'error', data: resp, error: err}

# TODO download and index are just copies of opendoar, should actually find out how to download and index sherpa
API.use.sherpa.romeo.download = () ->
  url = ''
  try
    res = HTTP.call 'GET', url
    if res.statusCode is 200
      js = API.convert.xml2json undefined,res.content
      data = []
      data.push(r) for r in js.
      return { total: js.length, data: data}
    else
      return { status: 'error', data: res}
  catch err
    return { status: 'error', error: err}

API.use.sherpa.romeo.index = () ->
  dl = API.use.sherpa.romeo.download()
  ret = {total:dl.total,success:0,error:0,errors:[]}
  for rec in dl.data
    res = API.es.insert '/opendoar/repository/' + rec._id, rec
    if not res.info?
      ret.success += 1
    else
      ret.errors.push res
      ret.error += 1
  return ret



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