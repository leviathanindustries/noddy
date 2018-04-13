
#import request from 'request'
import { Converter } from 'csvtojson'
import json2csv from 'json2csv'
import html2txt from 'html-to-text'
import textract from 'textract' # note this requires installs on the server for most conversions
import xml2js from 'xml2js'
import PDFParser from 'pdf2json'

import canvg from 'canvg'
import atob from 'atob'
import Canvas from 'canvas' # not canvas requires sudo apt-get install libcairo2-dev libjpeg-dev libpango1.0-dev libgif-dev build-essential g++

import Future from 'fibers/future'



API.convert = {}

API.add 'convert',
  desc: 'Convert files from one format to another. Provide content to convert as either "url" or "content" query param, or POST content as request body.
        Also provide "from" and "to" query params to identify the formats to convert from and to. It is also possible to provide a
        comma-separated list of "fields", which when converting from JSON will result in only those fields being used in the output (does
        not handle deep nesting). The currently available conversions are: svg to png. table to json or csv. csv to json or text.
        html to text. json to csv or text (or json again, which with "fields" can simplify json data). xml to text or json.
        pdf to text or json (which provides content and metadata). More conversions are possible, but require additional installations
        on the API machine, which are not turned on by default.'
  get: () ->
    if this.queryParams.url or this.queryParams.content or this.queryParams.es
      this.queryParams.fields = this.queryParams.fields.split(',') if this.queryParams.fields
      this.queryParams.from = 'txt' if this.queryParams.from is 'text'
      this.queryParams.to = 'txt' if this.queryParams.to is 'text'
      to = 'text/plain'
      to = 'text/csv' if this.queryParams.to is 'csv'
      to = 'image/png' if this.queryParams.to is 'png'
      to = 'application/' + this.queryParams.to if this.queryParams.to is 'json' or this.queryParams.to is 'xml'
      out = API.convert.run this.queryParams.url, this.queryParams.from, this.queryParams.to, this.queryParams.content, this.queryParams
      to = 'application/json' if typeof out is 'object'
      try return out if out.statusCode is 401 or out.status is 'error'
      if to is 'text/csv'
        this.response.writeHead 200,
          'Content-disposition': "attachment; filename=convert.csv"
          'Content-type': to + '; charset=UTF-8'
          'Content-Encoding': 'UTF-8'
        this.response.end out
        this.done()
      else
        return
          statusCode: 200
          headers:
            'Content-Type': to
          body: out
    else
      return {data: 'Accepts URLs of content files and converts them. from csv to json,txt. from html to txt. from xml to txt, json. from pdf to txt. from file to txt. For json to csv a subset param can be provided, giving dot notation to the part of the json object that should be converted.'}
  post: () ->
    this.queryParams.fields = this.queryParams.fields.split(',') if this.queryParams.fields
    this.queryParams.from = 'txt' if this.queryParams.from is 'text'
    this.queryParams.to = 'txt' if this.queryParams.to is 'text'
    to = 'text/plain'
    to = 'text/csv' if this.queryParams.to is 'csv'
    to = 'image/png' if this.queryParams.to is 'png'
    to = 'application/' + this.queryParams.to if this.queryParams.to is 'json' or this.queryParams.to is 'xml'
    out = API.convert.run undefined, this.queryParams.from, this.queryParams.to, this.request.body, this.queryParams
    to = 'application/json' if typeof out is 'object'
    try return out if out.statusCode is 401
    if to is 'text/csv'
      this.response.writeHead 200,
        'Content-disposition': "attachment; filename=convert.csv"
        'Content-type': to + '; charset=UTF-8'
        'Content-Encoding': 'UTF-8'
      this.response.end out
      this.done()
    else
      return
        statusCode: 200
        headers:
          'Content-Type': to
        body: out
  

API.convert.run = (url,from,to,content,opts) ->
  from ?= opts.from
  to ?= opts.to
  if from is 'svg'
    if to is 'png'
      output = API.convert.svg2png(url,content,opts)
  else if from is 'table'
    if to.indexOf('json') isnt -1
      output = API.convert.table2json(url,content,opts)
    else if to.indexOf('csv') isnt -1
      output = API.convert.table2csv(url,content,opts)
  else if from is 'csv'
    if to.indexOf('json') isnt -1
      output = API.convert.csv2json(url,content,opts)
    else if to.indexOf('txt') isnt -1
      from = 'file'
  else if from is 'html'
    if to.indexOf('txt') isnt -1
      output = API.convert.html2txt(url,content)
  else if from is 'json'
    if opts.es
      user = API.accounts.retrieve({apikey:opts.apikey}) if opts.apikey
      uid = if user then user._id else undefined # because could be querying a public ES endpoint
      params = {}
      if opts.es.indexOf('?') isnt -1
        prs = opts.es.split('?')[1]
        parts = prs.split('&')
        for p in parts
          kp = p.split('=')
          params[kp[0]] = kp[1]
      opts.es = opts.es.split('?')[0]
      opts.es = opts.es.substring(1,opts.es.length-1) if opts.es.substring(0,1) is '/'
      rts = opts.es.split('/')
      content = API.es.action(uid,'GET',rts,params)
      return content if content.statusCode is 401
      delete opts.es
      delete opts.apikey
      url = undefined
    if to.indexOf('csv') isnt -1
      output = API.convert.json2csv(opts,url,content)
    else if to.indexOf('txt') isnt -1
      from = 'file'
    else if to.indexOf('json') isnt -1
      output = API.convert.json2json(opts,url,content)
  else if from is 'xml'
    if to.indexOf('txt') isnt -1
      output = API.convert.xml2txt(url,content)
    else if to.indexOf('json') isnt -1
      output = API.convert.xml2json(url,content)
  else if from is 'pdf'
    if to.indexOf('txt') isnt -1
      output = API.convert.pdf2txt(url,content,opts)
    else if to.indexOf('json') isnt -1
      output = API.convert.pdf2json(url,content,opts)
  if from is 'file' # some of the above switch to this, so separate loop
    if to.indexOf('txt') isnt -1
      output = API.convert.file2txt(url,content,opts)
  if not output?
    return {status: 'error', data: 'conversion from ' + from + ' to ' + to + ' is not currently possible.'}
  else
    return output



API.convert.svg2png = (url,content,opts) ->
  content = if url? then HTTP.call('GET',url,{npmRequestOptions:{encoding:null}}).content else content
  content = content.toString('utf-8') if Buffer.isBuffer content
  content = atob(content.substring('data:image/svg+xml;base64,'.length)) if content.indexOf('data:image/svg+xml;base64,') >= 0
  canvas = new Canvas()
  canvg canvas, content, { ignoreMouse: true, ignoreAnimation: true, ImageClass: Canvas.Image }
  stream = canvas.pngStream()
  data = []
  done = false
  stream.on 'data', (chunk) -> data.push chunk
  stream.on 'end', () -> done = true
  while not done
    future = new Future()
    Meteor.setTimeout (() -> future.return()), 500
    future.wait()
  return Buffer.concat data

API.convert.csv2json = Async.wrap (url,content,opts,callback) ->
  if typeof content is 'function'
    callback = content
    content = undefined
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  converter
  if not content?
    converter = new Converter({constructResult:false})
    recs = []
    converter.on "record_parsed", (row) -> recs.push(row)
    #request.get(url).pipe(converter);
    HTTP.call('GET',url).pipe(converter)
    return recs # this probably needs to be on end of data stream
  else
    converter = new Converter({})
    converter.fromString content, (err,result) -> return callback(null,result)

API.convert.table2json = (url,content,opts) ->
  content = HTTP.call('GET', url).content if url?
  content = content.split(opts.start)[1] if opts.start
  if content.indexOf('<table') isnt -1
    content = '<table' + content.split('<table')[1]
  else if content.indexOf('<TABLE') isnt -1
    content = '<TABLE' + content.split('<TABLE')[1]
  content = content.split(opts.end)[0] if opts.end
  if content.indexOf('</table') isnt -1
    content = content.split('</table')[0] + '</table>'
  else if content.indexOf('</TABLE') isnt -1
    content = content.split('</TABLE')[1] + '</TABLE>'
  content = content.replace(/\\n/gi,'')
  ths = content.match(/<th.*?<\/th/gi)
  headers = []
  results = []
  for h in ths
    str = h.replace(/<th.*?>/i,'').replace(/<\/th.*?/i,'').replace(/<.*?>/gi,'').replace(/&nbsp;/gi,'')
    str = 'UNKNOWN' if str.replace(/ /g,'').length is 0
    headers.push str
  rows = content.match(/<tr.*?<\/tr/gi)
  for r in rows
    if r.toLowerCase().indexOf('<th') is -1
      result = {}
      row = rowsr.replace(/<tr.*?>/i,'').replace(/<\/tr.*?/i,'')
      vals = row.match(/<td.*?<\/td/gi)
      for d of vals
        keycounter = parseInt d
        if vals[d].toLowerCase().indexOf('colspan') isnt -1
          try
            count = parseInt(vals[d].toLowerCase().split('colspan')[1].split('>')[0].replace(/[^0-9]/,''))
            keycounter += (count-1)
        val = vals[d].replace(/<.*?>/gi,'').replace('</td','')
        if headers.length > keycounter
          result[headers[keycounter]] = val
      delete result.UNKNOWN if result.UNKNOWN?
      results.push result
  return results

API.convert.table2csv = (url,content,opts) ->
  d = API.convert.table2json(url,content,opts)
  return API.convert.json2csv(undefined,undefined,d)

API.convert.html2txt = (url,content) ->
  # should this use phantomjs, to get text content before rendering to text?
  content = HTTP.call('GET', url).content if url?
  text = html2txt.fromString(content, {wordwrap: 130})
  return text

API.convert.file2txt = Async.wrap (url, content, opts={}, callback) ->
  if typeof content is 'function'
    callback = content
    content = undefined
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  # NOTE for this to work, see textract on npm - requires other things (antiword for word docs) installed. May not be useful.
  from = opts.from ? 'application/msword'
  delete opts.from
  content = new Buffer (if url? then HTTP.call('GET',url,{npmRequestOptions:{encoding:null}}).content else content)
  textract.fromBufferWithMime from, content, opts, ( err, result ) ->
    return callback(null,result)

API.convert.pdf2txt = Async.wrap (url, content, opts={}, callback) ->
  if typeof content is 'function'
    callback = content
    content = undefined
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  pdfParser = new PDFParser(this,1)
  pdfParser.on "pdfParser_dataReady", (pdfData) ->
    return callback(null,pdfParser.getRawTextContent())
  content = new Buffer (if url? then HTTP.call('GET',url,{npmRequestOptions:{encoding:null}}).content else content)
  pdfParser.parseBuffer(content)

API.convert.pdf2json = Async.wrap (url, content, opts={}, callback) ->
  if typeof content is 'function'
    callback = content
    content = undefined
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  pdfParser = new PDFParser();
  pdfParser.on "pdfParser_dataReady", (pdfData) ->
    return callback(null,pdfData)
  content = new Buffer (if url? then HTTP.call('GET',url,{npmRequestOptions:{encoding:null}}).content else content)
  pdfParser.parseBuffer(content)

API.convert.xml2txt = (url,content) ->
  return API.convert.file2txt(url,content,{from:'application/xml'})

API.convert.xml2json = Async.wrap (url, content, callback) ->
  if typeof content is 'function'
    callback = content
    content = undefined
  content = HTTP.call('GET', url).content if url?
  parser = new xml2js.Parser()
  parser.parseString content, (err, result) -> return callback(null,result)

# using meteorhacks:async and Async.wrap seems to work better than using Meteor.wrapAsync
API.convert.json2csv = Async.wrap (opts={}, url, content, callback) ->
  if typeof url is 'function'
    content = url
    url = undefined
  if typeof content is 'function'
    callback = content
    content = undefined
  console.log(content.length) if content # KEEP THIS HERE - oddly, having this here stops endpoints throwing a write before end error and crashing the app when they try to serve out the csv, so just keep this here
  content = JSON.parse(HTTP.call('GET', url).content) if url?
  if opts.subset
    parts = opts.subset.split('.')
    delete opts.subset
    for p in parts
      if Array.isArray(content)
        c = []
        for r in content
          c.push(r[p])
        content = c
      else
        content = content[p]
  for l in content
    for k in l
      k = k.join(',') if Array.isArray(k)
  opts.data = content
  json2csv opts, (err, result) ->
    result = result.replace(/\\r\\n/g,'\r\n') if result
    return callback(null,result)

API.convert.json2json = (opts,url,content) ->
  content = HTTP.call('GET', url).content if url?
  if opts.subset
    parts = opts.subset.split('.')
    content = content[s] for s in parts
  if opts.fields
    recs = []
    for r in content
      rec = {}
      rec[f] = r[f] for f in opts.fields
      recs.push rec
    content = recs
  return content



################################################################################
###
API.add 'convert/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.convert.test this.queryParams.fixtures


API.convert.test = (fixtures) ->

  console.log('Starting convert test') if API.settings.dev

  if (fixtures === undefined && API.settings.fixtures && API.settings.fixtures.url) fixtures = API.settings.fixtures.url;
  if (fixtures === undefined) return {passed: false, failed: [], NOTE: 'fixtures.url MUST BE PROVIDED IN SETTINGS FOR THIS TEST TO RUN, and must point to a folder containing files called test in csv, html, pdf, xml and json format'}

  var result = {failed:[]};

  result.csv2json = API.convert.run(fixtures + 'test.csv','csv','json');

  result.table2json = API.convert.run(fixtures + 'test.html','table','json');

  result.html2txt = API.convert.run(fixtures + 'test.html','html','txt');

  //result.file2txt = API.convert.run(fixtures + 'test.doc','file','txt');

  result.pdf2txt = API.convert.run(fixtures + 'test.doc','pdf','txt');

  result.xml2txt = API.convert.run(fixtures + 'test.xml','xml','txt');

  result.xml2json = API.convert.run(fixtures + 'test.xml','xml','json');

  result.json2csv = API.convert.run(fixtures + 'test.json','json','csv');

  result.json2json = API.convert.run(fixtures + 'test.json','json','json');

  result.passed = result.passed isnt false and result.failed.length is 0

  console.log('Ending collection test') if API.settings.dev

  return result



###