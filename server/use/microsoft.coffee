
# use microsoft

API.add 'use/microsoft', get: () -> return {info: 'returns microsoft things a bit nicer'}

API.add 'use/microsoft/academic/evaluate', get: () -> return API.use.microsoft.academic.evaluate this.queryParams

API.use ?= {}
API.use.microsoft = {}
API.use.microsoft.academic = {}

# https://docs.microsoft.com/en-gb/azure/cognitive-services/academic-knowledge/queryexpressionsyntax
# https://docs.microsoft.com/en-gb/azure/cognitive-services/academic-knowledge/paperentityattributes
# https://westus.dev.cognitive.microsoft.com/docs/services/56332331778daf02acc0a50b/operations/5951f78363b4fb31286b8ef4/console
# https://portal.azure.com/#resource/subscriptions

API.use.microsoft.academic.evaluate = (qry, attributes='Id,Ti,Y,D,CC,W,AA.AuN,J.JN,E') ->
  # things we accept as query params have to be translated into MS query expression terminology
  # we will only do the ones we need to do... for now that is just title :)
  # It does not seem possible to search on the extended metadata such as DOI, 
  # and extended metadata always seems to come back as string, so needs converting back to json
  expr = ''
  for t of qry
    expr = encodeURIComponent("Ti='" + qry[t] + "'") if t is 'title'
  url = 'https://westus.api.cognitive.microsoft.com/academic/v1.0/evaluate?expr='+expr + '&attributes=' + attributes
  API.log 'Using microsoft academic for ' + url
  try
    res = HTTP.call 'GET', url, {headers: {'Ocp-Apim-Subscription-Key': API.settings.use.microsoft.academic.key}}
    if res.statusCode is 200
      for r in res.data.entities
        r.extended = JSON.parse(r.E) if r.E
        r.converted = {
          title: r.Ti,
          journal: r.J?.JN,
          author: []
        }
        r.converted.author.push({name:r.AA[a].AuN}) for a in r.AA
        try r.converted.url = r.extended.S[0].U
        # TODO could parse more of extended into converted, and change result to just converted if we don't need the original junk
      return res.data
    else
      return { status: 'error', data: res.data}
  catch err
    return { status: 'error', data: 'error', error: err}
