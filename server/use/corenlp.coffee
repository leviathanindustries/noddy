
# use stanford corenlp web service - so, requires corenlp running somewhere and the URL to the web service for it
# https://nlp.stanford.edu/software/CRF-NER.shtml
# https://stanfordnlp.github.io/CoreNLP/corenlp-server.html

# downloaded and installed on main machine - upgraded the java to 8 first (note index machines use 7, hence why not on that machine)
# https://stanfordnlp.github.io/CoreNLP/index.html#download
# only running from screen for now, but can install properly, see corenlp-server link above for instructions
# run command in a screen:
# java -mx4g -cp "*" edu.stanford.nlp.pipeline.StanfordCoreNLPServer -port 9000 -timeout 30000
# not enough memory on main machine and running it with 1g fails, moving to a dedicated one
# 4g OOMed at first load as well, moved up to 7g. That worked, and did not seem to go over 5g, so perhaps that would do
# also managed to time out on text extracted from a 5 page pdf so increased timeout to 60000
# did see pushes of memory usage over 6gb parsing pdf files for entities

# java -mx6g -cp "*" edu.stanford.nlp.pipeline.StanfordCoreNLPServer -port 9000 -timeout 60000

API.use ?= {}
API.use.corenlp = {}

API.add 'use/corenlp', 
  get: () -> return API.use.corenlp.run this.queryParams.q, this.queryParams
  post: () -> return API.use.corenlp.run (this.bodyParams.content ? this.request.body), (this.bodyParams.options ? this.queryParams)

API.add 'use/corenlp/:fn', 
  get: () -> return API.use.corenlp[this.urlParams.fn] this.queryParams.q, this.queryParams
  post: () -> return API.use.corenlp[this.urlParams.fn] (this.bodyParams.content ? this.request.body), (this.bodyParams.options ? this.queryParams)


API.use.corenlp.run = (q, options, cache=false, url='http://10.131.124.133:9000') ->
  # options are like this, see docs for all of them {"annotators":"tokenize,ssplit,pos","outputFormat":"json"}
  # all possible annotators seem to be:
  # tokenize,ssplit,pos,lemma,ner,parse,depparse,natlog,coref,openie,kbp
  if _.isArray options
    options = {annotators: options.join(',')}
  else if typeof options is 'string'
    options = {annotators: options}
  try delete options.raw
  try delete options.q

  if cache
    checksum = API.job.sign q, options
    exists = API.http.cache checksum, 'corenlp_run'
    return exists if exists

  url ?= API.settings.use?.corenlp?.url
  if options?
    try url += '?properties=' + JSON.stringify options
  res = HTTP.call 'POST', url, {content:q, headers:{'Content-Type':'text/plain'}}
  if res.data
    if cache
      API.http.cache checksum, 'corenlp_run', res.data
    return res.data
  else
    return res

API.use.corenlp.entities = (q, options={}, cache, url) ->
  # ner is entity recognition
  options.annotators ?= 'ner'
  return API.use.corenlp.run q, options, cache, url
