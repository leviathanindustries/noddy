
#import request from 'request'
import { Converter } from 'csvtojson'
import json2csv from 'json2csv'
import textract from 'textract' # note this requires installs on the server for most conversions
import mammoth from 'mammoth'
import xlsx from 'xlsx'
import xml2js from 'xml2js'
import PDFParser from 'pdf2json'
import stream from 'stream'
import html2txt from 'html-to-text'

#import canvg from 'canvg'
import atob from 'atob'
#import Canvas from 'canvas' # note canvas requires sudo apt-get install libcairo2-dev libjpeg-dev libpango1.0-dev libgif-dev build-essential g++
# canvas and canvg cannot be installed in a working manner any more, need to find an alternative solution later
# canvg may still be ok. Actually these will both run, it is their underlying libs on ubuntu that cannot run

import Future from 'fibers/future'
import moment from 'moment'



API.convert = {}

API.add 'convert',
  desc: 'Convert files from one format to another. Provide content to convert as either "url" or "content" query param, or POST content as request body.
        Also provide "from" and "to" query params to identify the formats to convert from and to. It is also possible to provide a
        comma-separated list of "fields", which when converting from JSON will result in only those fields being used in the output (does
        not handle deep nesting). The currently available conversions are: svg to png. table to json or csv. csv to json or html or text.
        html to text. json to csv or text (or json again, which with "fields" can simplify json data). xml to text or json.
        pdf to text or json (which provides content and metadata). xls to json or csv or html or txt. google sheet (sheet) to json or csv or html or txt. 
        list to string takes a json list of objects and convert it to a string. 
        More conversions are possible, but require additional installations on the API machine, which are not turned on by default.'
  get: () ->
    if this.queryParams.url or this.queryParams.content or this.queryParams.es
      this.queryParams.fields = this.queryParams.fields.split(',') if this.queryParams.fields
      this.queryParams.from = 'xls' if this.queryParams.from in ['excel','xlsx']
      this.queryParams.from = 'txt' if this.queryParams.from is 'text'
      this.queryParams.to = 'txt' if this.queryParams.to is 'text'
      this.queryParams.to = 'html' if this.queryParams.to is 'table' and this.queryParams.from in ['json','csv']
      to = 'text/plain'
      to = 'text/csv' if this.queryParams.to is 'csv'
      to = 'image/png' if this.queryParams.to is 'png'
      to = 'application/' + this.queryParams.to if this.queryParams.to is 'json' or this.queryParams.to is 'xml'
      to = 'text/html' if this.queryParams.to is 'html'
      out = API.convert.run (this.queryParams.url ? this.queryParams.content), this.queryParams.from, this.queryParams.to, this.queryParams
      to = 'application/json' if typeof out is 'object'
      try return out if out.statusCode is 401 or out.status is 'error'
      if to is 'text/csv'
        this.response.writeHead 200,
          'Content-disposition': "attachment; filename=convert.csv"
          'Content-type': to + '; charset=UTF-8'
          'Content-Encoding': 'UTF-8'
        this.response.end out
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
    this.queryParams.from = 'xls' if this.queryParams.from in ['excel','xlsx']
    this.queryParams.from = 'txt' if this.queryParams.from is 'text'
    this.queryParams.to = 'txt' if this.queryParams.to is 'text'
    this.queryParams.to = 'html' if this.queryParams.to is 'table' and this.queryParams.from in ['json','csv']
    to = 'text/plain'
    to = 'text/csv' if this.queryParams.to is 'csv'
    to = 'image/png' if this.queryParams.to is 'png'
    to = 'application/' + this.queryParams.to if this.queryParams.to is 'json' or this.queryParams.to is 'xml'
    out = API.convert.run (if this.request.files? and this.request.files.length > 0 then this.request.files[0].data else this.request.body), this.queryParams.from, this.queryParams.to, this.queryParams
    to = 'application/json' if typeof out is 'object'
    try return out if out.statusCode is 401 or out.status is 'error'
    if to is 'text/csv'
      this.response.writeHead 200,
        'Content-disposition': "attachment; filename=convert.csv"
        'Content-type': to + '; charset=UTF-8'
        'Content-Encoding': 'UTF-8'
      this.response.end out
    else
      return
        statusCode: 200
        headers:
          'Content-Type': to
        body: out
  

API.convert.run = (content,from,to,opts={}) ->
  from ?= opts.from
  to ?= opts.to
  if from is 'svg' and to is 'png'
    output = API.convert.svg2png(content,opts)
  else if from is 'table' and to in ['json','csv']
    output = API.convert['table2' + to](content,opts)
  else if from is 'csv'
    if to.indexOf('json') isnt -1
      output = API.convert.csv2json(content,opts)
    else if to.indexOf('html') isnt -1
      content = API.convert.csv2json content, opts
      workbook = xlsx.utils.json_to_sheet content
      output = API.convert._workbook2 'html', workbook, opts
    else if to.indexOf('txt') isnt -1
      from = 'file'
  else if from is 'html' and to.indexOf('txt') isnt -1
    output = API.convert.html2txt(content)
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
    if to.indexOf('csv') isnt -1
      output = API.convert.json2csv(content,opts)
    if to.indexOf('html') isnt -1
      workbook = xlsx.utils.json_to_sheet content
      output = API.convert._workbook2 'html', workbook, opts
    else if to.indexOf('txt') isnt -1
      from = 'file'
    else if to.indexOf('json') isnt -1
      output = API.convert.json2json(content,opts)
  else if from is 'xml' and to in ['txt','json']
    output = API.convert['xml2' + to](content)
  else if from is 'pdf' and to in ['txt','json']
    output = API.convert['pdf2' + to](content,opts)
  else if from is 'docx' and to in ['txt','text']
    output = API.convert.docx2txt content, opts
  else if from is 'docx' and to is 'html'
    output = API.convert.docx2html content, opts
  else if from is 'docx' and to is 'markdown'
    output = API.convert.docx2markdown content, opts
  else if from in ['xls','sheet','list'] and to in ['txt','json','html','csv','string']
    output = API.convert[from + '2' + to](content,opts)
  if from is 'file' and to.indexOf('txt') isnt -1 # some of the above switch to this, so separate loop
    output = API.convert.file2txt(content,opts)
  if not output?
    return {status: 'error', data: 'conversion from ' + from + ' to ' + to + ' is not currently possible.'}
  else
    return output



API.convert.svg2png = (content,opts) ->
  return false # need alternative to canvas and canvg for newer ubuntu where they try to use old libgif4 that can no longer run
  '''content = HTTP.call('GET',content,{npmRequestOptions:{encoding:null}}).content if content.indexOf('http') is 0
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
  return Buffer.concat data'''

API.convert.csv2json = Async.wrap (content,opts,callback) ->
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  converter
  if content.indexOf('http') is 0
    converter = new Converter({constructResult:false})
    recs = []
    converter.on "record_parsed", (row) -> recs.push(row)
    #request.get(content).pipe(converter);
    HTTP.call('GET',content).pipe(converter)
    return recs # this probably needs to be on end of data stream
  else
    converter = new Converter({})
    converter.fromString content, (err,result) -> 
      return callback(null,result)

API.convert.table2json = (content,opts) ->
  content = HTTP.call('GET', content).content if content.indexOf('http') is 0
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

API.convert.table2csv = (content,opts) ->
  d = API.convert.table2json(content,opts)
  return API.convert.json2csv(d)

API.convert.html2txt = (content,render=false) ->
  if content.indexOf('http') is 0
    content = if render then API.http.puppeteer(content) else HTTP.call('GET', content).content
  text = html2txt.fromString(content, {wordwrap: 130})
  return text

API.convert.mime = (fn) ->
  # plus some programming languages with text/plain, useful for filtering on filenames
  mimes = {
    '.aac': 'audio/aac', # AAC audio	
    '.abw': 'application/x-abiword', # AbiWord document
    '.arc': 'application/x-freearc', # Archive document (multiple files embedded)
    '.avi': 'video/x-msvideo', # AVI: Audio Video Interleave
    '.azw': 'application/vnd.amazon.ebook', # Amazon Kindle eBook format
    '.bin': 'application/octet-stream', # Any kind of binary data
    '.bmp': 'image/bmp', # Windows OS/2 Bitmap Graphics
    '.bz': 'application/x-bzip', # BZip archive
    '.bz2': 'application/x-bzip2', # BZip2 archive
    '.csh': 'application/x-csh', # C-Shell script
    '.css': 'text/css', # Cascading Style Sheets (CSS)
    '.csv': 'text/csv', # Comma-separated values (CSV)
    '.doc': 'application/msword', # Microsoft Word
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', # Microsoft Word (OpenXML)
    '.eot': 'application/vnd.ms-fontobject', # MS Embedded OpenType fonts
    '.epub': 'application/epub+zip', # Electronic publication (EPUB)
    '.gz': 'application/gzip', # GZip Compressed Archive
    '.gif': 'image/gif', # Graphics Interchange Format (GIF)
    '.htm': 'text/html', # HyperText Markup Language (HTML)
    '.ico': 'image/vnd.microsoft.icon', # Icon format
    '.ics': 'text/calendar', # iCalendar format
    '.jar': 'application/java-archive', # Java Archive (JAR)
    '.jpg': 'image/jpeg', # JPEG images
    '.js': 'text/javascript', # JavaScript
    '.json': 'application/json', # JSON format
    '.jsonld': 'application/ld+json', # JSON-LD format
    '.mid': 'audio/midi', # Musical Instrument Digital Interface (MIDI) audio/x-midi
    '.mjs': 'text/javascript', # JavaScript module
    '.mp3': 'audio/mpeg', # MP3 audio
    '.mpeg': 'video/mpeg', # MPEG Video
    '.mpkg': 'application/vnd.apple.installer+xml', # Apple Installer Package
    '.odp': 'application/vnd.oasis.opendocument.presentation', # OpenDocument presentation document
    '.ods': 'application/vnd.oasis.opendocument.spreadsheet', # OpenDocument spreadsheet document
    '.odt': 'application/vnd.oasis.opendocument.text', # OpenDocument text document
    '.oga': 'audio/ogg', # OGG audio
    '.ogv': 'video/ogg', # OGG video
    '.ogx': 'application/ogg', # OGG
    '.opus': 'audio/opus', # Opus audio
    '.otf': 'font/otf', # OpenType font
    '.png': 'image/png', # Portable Network Graphics
    '.pdf': 'application/pdf', # Adobe Portable Document Format (PDF)
    '.php': 'application/php', # Hypertext Preprocessor (Personal Home Page)
    '.ppt': 'application/vnd.ms-powerpoint', # Microsoft PowerPoint
    '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation', # Microsoft PowerPoint (OpenXML)
    '.py': 'text/plain',
    '.rar': 'application/vnd.rar', # RAR archive
    '.rb': 'text/plain',
    '.rtf': 'application/rtf', # Rich Text Format (RTF)
    '.sh': 'application/x-sh', # Bourne shell script
    '.svg': 'image/svg+xml', # Scalable Vector Graphics (SVG)
    '.swf': 'application/x-shockwave-flash', # Small web format (SWF) or Adobe Flash document
    '.tar': 'application/x-tar', # Tape Archive (TAR)
    '.tif': 'image/tiff', # Tagged Image File Format (TIFF)
    '.ts': 'video/mp2t', # MPEG transport stream
    '.ttf': 'font/ttf', # TrueType Font
    '.txt': 'text/plain', # Text, (generally ASCII or ISO 8859-n)
    '.vsd': 'application/vnd.visio', # Microsoft Visio
    '.wav': 'audio/wav', # Waveform Audio Format
    '.weba': 'audio/webm', # WEBM audio
    '.webm': 'video/webm', # WEBM video
    '.webp': 'image/webp', # WEBP image
    '.woff': 'font/woff', # Web Open Font Format (WOFF)
    '.woff2': 'font/woff2', # Web Open Font Format (WOFF)
    '.xhtml': 'application/xhtml+xml', # XHTML
    '.xls': 'application/vnd.ms-excel', # Microsoft Excel
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', # Microsoft Excel (OpenXML)
    '.xml': 'application/xml', # XML
    '.xul': 'application/vnd.mozilla.xul+xml', # XUL
    '.zip': 'application/zip', # ZIP archive
    '.3gp': 'video/3gpp', # 3GPP audio/video container audio/3gpp if it doesn't contain video
    '.3g2': 'video/3gpp2', # 3GPP2 audio/video container audio/3gpp2 if it doesn't contain video
    '.7z': 'application/x-7z-compressed' # 7-zip archive
  }
  tp = (if fn.indexOf('.') is -1 then fn else fn.substr(fn.lastIndexOf('.')+1)).toLowerCase()
  tp = 'htm' if tp is 'html'
  tp = 'jpg' if tp is 'jpeg'
  tp = 'tif' if tp is 'tiff'
  tp = 'mid' if tp is 'midi'
  mime = mimes['.'+tp]
  return if typeof mime is 'string' then mime else false

API.convert._docx2 = Async.wrap (what='txt', content, opts={}, callback) ->
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  if typeof content is 'string' and content.indexOf('http') is 0
    content = API.http.getFile(content).data
  if typeof content is 'string'
    content = new Buffer content
  try
    # NOTE the convert to html fails within mammoth, but txt and markdown both work. Could add a markdown to html converter later if necessary
    # some mammoth calls just go off into nowhere - need a way to return, but it throws no error no done...
    mammoth[(if what is 'html' then 'convertToHTML' else if what is 'markdown' then 'convertToMarkdown' else 'extractRawText')]({buffer: content})
      .then((res) ->
        return callback null, res.value
      ).done()
  catch
    return callback null, ''
API.convert.docx2txt = (content, opts={}) -> return API.convert._docx2 'txt', content, opts
API.convert.docx2html = (content, opts={}) -> return API.convert._docx2 'html', content, opts
API.convert.docx2markdown = (content, opts={}) -> return API.convert._docx2 'markdown', content, opts

API.convert.file2txt = Async.wrap (content, opts={}, callback) ->
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  # NOTE for this to work, see textract on npm - requires other things (antiword for word docs) installed. May not be useful.
  opts.from = undefined if typeof opts.from is 'string' and opts.from.indexOf('/') is -1 # need a proper mime type here
  from = opts.from
  delete opts.from
  named = opts.name ? false
  delete opts.name
  if named and not from
    mime = API.convert.mime named
    if mime
      from = mime
      named = false
  from ?= 'application/msword'
  return API.convert.docx2txt(content, opts) if (typeof content is 'string' and content.split('?')[0].endsWith('.docx')) or (typeof named is 'string' and content.split('?')[0].endsWith('.docx'))
  try
    if typeof content is 'string' and content.indexOf('http') is 0
      textract.fromUrl content, opts, ( err, result ) ->
        return callback null, result
    else if named
      if typeof content is 'string'
        content = new Buffer content
      textract.fromBufferWithName named, content, opts, ( err, result ) ->
        return callback null, result
    else
      if typeof content is 'string'
        content = new Buffer content
      textract.fromBufferWithMime from, content, opts, ( err, result ) ->
        return callback null, result
  catch
    return callback null, ''

# xlsx has lots more useful options that could be used to get particular parts of sheets. See:
# https://www.npmjs.com/package/xlsx
API.convert._workbook2 = (what='csv', workbook, opts={}) ->
  # add some options to crop to certain rows here
  try
    res = xlsx.utils['sheet_to_' + what] workbook # this works if just one simple sheet
  catch
    sheets = workbook.SheetNames # this works if it is a sheet with names
    opts.sheet ?= sheets[0]
    res = xlsx.utils['sheet_to_' + what] workbook.Sheets[opts.sheet]
  res = res.split('<body>')[1].split('</body>')[0] if what is 'html'
  return res
API.convert._xls2 = (what='csv', content, opts={}) ->
  content = new Buffer (if content.indexOf('http') is 0 then HTTP.call('GET',content,{npmRequestOptions:{encoding:null}}).content else content)
  workbook = xlsx.read content
  return API.convert._workbook2 what, workbook, opts
API.convert._sheet2 = (what='csv', content, opts={}) ->
  content = API.use.google.sheets.feed content, opts
  workbook = xlsx.utils.json_to_sheet content
  return API.convert._workbook2 what, workbook, opts
API.convert.xls2txt = (content, opts={}) -> return API.convert._xls2 'txt', content, opts
API.convert.xls2html = (content, opts={}) -> return API.convert._xls2 'html', content, opts
API.convert.xls2json = (content, opts={}) -> return API.convert._xls2 'json', content, opts
API.convert.xls2csv = (content, opts={}) -> return API.convert._xls2 'csv', content, opts
API.convert.sheet2txt = (content, opts={}) -> return API.convert._sheet2 'txt', content, opts
API.convert.sheet2html = (content, opts={}) -> return API.convert._sheet2 'html', content, opts
API.convert.sheet2csv = (content, opts={}) -> return API.convert._sheet2 'csv', content, opts
API.convert.sheet2json = (content, opts={}) -> return API.convert._sheet2 'json', content, opts

API.convert.pdf2txt = Async.wrap (content, opts={}, callback) ->
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  opts.timeout ?= 20000
  pdfParser = new PDFParser(this,1)
  completed = false
  pdfParser.on "pdfParser_dataReady", (pdfData) ->
    completed = true
    if not pdfParser?
      return callback(null,'')
    else if opts.raw
      return callback null, pdfData
    else if opts.metadata
      return callback null, pdfData.formImage.Id
    else if opts.newlines isnt true and opts.pages isnt true
      strs = []
      for p in pdfData.formImage.Pages
        for t in p.Texts
          for s in t.R
            strs.push decodeURIComponent s.T
      return callback null, if opts.list then strs else strs.join(' ')
    else
      res = pdfParser.getRawTextContent()
      res = res.replace(/\r\n/g,'\n')
      if opts.newlines isnt true
        res = res.replace(/\n/g,' ')
      if opts.pages isnt true
        res = res.replace(/----------------Page \([0-9].*?\) Break----------------/g,' ')
      return callback(null,res)
  # TODO some PDFs are capable of causing an error within the parser that it fails to catch - this needs further investigation at some point
  # https://dev.openaccessbutton.org/static/test-manuscripts/Unwelcome_Change-_Coming_to_Terms_with_Democratic_Backsliding_Lust.pdf
  # https://dev.openaccessbutton.org/static/test-manuscripts/weitz_hair_and_power_article.pdf
  pdfParser.on "pdfParser_dataError", (err) ->
    completed = true
    return callback(null,'')
  try
    console.log('CONVERT PDF retrieving from ' + content) if content.indexOf('http') is 0 and API.settings.dev
    content = new Buffer (if content.indexOf('http') is 0 then HTTP.call('GET',content,{timeout:opts.timeout,npmRequestOptions:{encoding:null}}).content else content)
    pdfParser.parseBuffer(content)
  catch
    return callback(null,'')
  # some PDF seem to cause an endless wait, such as 
  # https://www.carolinaperformingarts.org/wp-content/uploads/2015/04/Butoh-Bibliography-guide.pdf
  # so only wait for up to a minute
  # but still found a worse problem. This URL:
  # https://www.thoracic.org/patients/patient-resources/breathing-in-america/resources/chapter-23-sleep-disordered-breathing.pdf
  # spikes cpu to 100% and never times out... weird. It does not take long to download normally. Have not figured out how to catch this...
  # and it makes the system unusable
  waited = 0
  if not completed
    while waited <= opts.timeout and completed isnt true
      future = new Future()
      Meteor.setTimeout (() -> future.return()), 5000
      future.wait()
      waited += 5000
    if not completed
      console.log 'PDF to text conversion timed out at ' + waited
      pdfParser = undefined # does this kill the async process??? - not really, TODO fix this so it does not keep running and eat the memory
      return callback(null,'')

API.convert.pdf2json = Async.wrap (content, opts={}, callback) ->
  if typeof opts isnt 'object'
    callback = opts
    opts = {}
  opts.timeout ?= 20000
  pdfParser = new PDFParser();
  pdfParser.on "pdfParser_dataReady", (pdfData) ->
    return callback(null,pdfData)
  pdfParser.on "pdfParser_dataError", () ->
    return callback(null,{})
  try
    content = new Buffer (if content.indexOf('http') is 0 then HTTP.call('GET',content,{timeout:20000,npmRequestOptions:{encoding:null}}).content else content)
    pdfParser.parseBuffer(content)
  catch
    return callback(null,{})
  waited = 0
  while waited < opts.timeout
    future = new Future()
    Meteor.setTimeout (() -> future.return()), 5000
    future.wait()
    waited += 5000
  return callback(null,{})

API.convert.xml2txt = (content) ->
  return API.convert.file2txt(content,{from:'application/xml'})

API.convert._xml2json = Async.wrap (content, callback) ->
  content = HTTP.call('GET', content).content if content.indexOf('http') is 0
  parser = new xml2js.Parser()
  parser.parseString content, (err, result) -> return callback(null,result)

# make a neater version of xml converted straight to json
API.convert._cleanJson = (val, k, clean) ->
  if typeof clean is 'function'
    val = clean(val, k)
  if _.isArray val
    vv = []
    singleKeyObjects = true
    for v in val
      if typeof v isnt 'string' or v.replace(/ /g,'').replace(/\n/g,'') isnt ''
        cv = API.convert._cleanJson v, k, clean
        singleKeyObjects = typeof cv is 'object' and not _.isArray(cv) and _.keys(cv).length is 1
        vv.push cv
      else
        singleKeyObjects = false
    if false #singleKeyObjects
      nv = []
      for sv in vv
        nv.push sv[_.keys(sv)[0]]
      val = nv
    else
      val = if vv.length then if vv.length is 1 and typeof vv[0] is 'string' then vv[0] else vv else ''
  else if typeof val is 'object'
    keys = _.keys(val)
    if keys.length is 1 and (keys[0].toLowerCase() is k.toLowerCase() or (k.toLowerCase().split('').pop() is 's' and keys[0].toLowerCase() is k.toLowerCase().slice(0, -1)))
      val = API.convert._cleanJson val[keys[0]], k, clean
    else if val.$?.key? and val._? and keys.length is 2
      nv = {}
      nv[val.$.key] = val._
      val = nv
    else if val.$? and _.keys(val.$).length is 1
      sk = _.keys(val.$)[0]
      val[sk] = val.$[sk] #API.convert._cleanJson val.$[sk], sk, clean
      delete val.$
    else if val.$? and typeof val.$ is 'object'
      unique = true
      for dk of val.$
        unique = dk not in keys
      if unique
        for dkk of val.$
          val[dkk] = val.$[dkk] #API.convert._cleanJson val.$[dkk], dkk, clean
        delete val.$
    ak = _.keys(val)
    if ak.length is 1 and typeof val[ak[0]] is 'string' and val[ak[0]].toLowerCase() is k.toLowerCase()
      val = ''
    else
      wk = _.without(ak,'_')
      for o of val
        val[o] = API.convert._cleanJson val[o], o, clean
        if o is '_' and typeof val[o] is 'string' and not val.value?
          if wk.length is 1 and val[wk[0]].toLowerCase() is k.toLowerCase()
            return val._
          else
            val.value = val._
            delete val._
  return val

API.convert.xml2json = (content, subset, clean=true) ->
  res = API.convert._xml2json content
  if clean is false
    return res
  else
    recs = []
    res = [res] if not _.isArray res
    for row in res
      for k of row
        row[k] = API.convert._cleanJson row[k], k, clean
      recs.push row
    return if recs.length is 1 then recs[0] else recs

# using meteorhacks:async and Async.wrap seems to work better than using Meteor.wrapAsync
API.convert.json2csv = (content, opts={}) ->
  content = JSON.parse(HTTP.call('GET', content).content) if typeof content is 'string' and content.indexOf('http') is 0
  content = JSON.parse JSON.stringify content
  content = [content] if typeof content is 'object' and not _.isArray content
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
  opts.fields = opts.fields.split(',') if typeof opts.fields is 'string'
  if not opts.fields?
    opts.fields = []
    for o of content
      if typeof content[o] isnt 'object'
        content[o] = {jsn_split_rw_list: content[o]}
        opts.fields.push('jsn_split_rw_list') if 'jsn_split_rw_list' not in opts.fields
      else
        l = content[o]
        for k of l
          if Array.isArray l[k]
            if l[k].length is 0 
              opts.fields.push(k) if opts.fields.indexOf(k) is -1
              l[k] = ''
            else if typeof l[k][0] is 'string' or typeof l[k][0] is 'number'
              opts.fields.push(k) if opts.fields.indexOf(k) is -1
              l[k] = l[k].join(',')
            else if opts.flat # not the same as the lib opts.flatten
              for tk of l[k]
                itk = k + '.' + tk
                opts.fields.push(itk) if opts.fields.indexOf(itk) is -1
                l[itk] ?= ''
                if typeof l[k][tk] is 'object' # and note this only goes down to objects in lists
                  for otk of l[k][tk]
                    etk = k + '.' + tk + '.' + otk
                    opts.fields.push(etk) if opts.fields.indexOf(etk) is -1
                    l[etk] ?= ''
                    l[etk] += (if l[etk].length then if typeof opts.flat is 'boolean' then ', ' else opts.flat else '') + (if _.isArray(l[k][tk][otk]) then l[k][tk][otk].join(',') else if typeof l[k][tk][otk] is 'object' then JSON.stringify(l[k][tk][otk]) else l[k][tk][otk])
                else # note this would lead to this level of nested values being piled into one field even if they came from separate objects
                  l[itk] += (if l[itk].length then if typeof opts.flat is 'boolean' then ', ' else opts.flat else '') + (if _.isArray(l[k][tk]) then l[k][tk].join(',') else if typeof l[k][tk] is 'object' then JSON.stringify(l[k][tk]) else l[k][tk])
            else
              opts.fields.push(k) if opts.fields.indexOf(k) is -1
              l[k] = JSON.stringify l[k]
          else
            opts.fields.push(k) if opts.fields.indexOf(k) is -1
  else if _.isArray(opts.fields) and opts.fields.length is 1
    for o of content
      if typeof content[o] isnt 'object'
        co = {}
        co[opts.fields[0]] = content[o]
        content[o] = co

  # an odd use of a stream here, passing it what is already a variable. But this 
  # avoids json2csv OOM errors which seem to occur even if the memory is not all used
  # moving to all stream at some point would be nice, but not done yet...
  tf = new json2csv.Transform opts
  res = ''
  rs = new stream.Readable
  rs.push JSON.stringify content
  rs.push null
  rs.pipe tf
  done = false
  tf.on 'data', (chunk) -> res += chunk
  tf.on 'end', () -> done = true
  while not done
    future = new Future()
    Meteor.setTimeout (() -> future.return()), 500
    future.wait()
  res = res.replace('"jsn_split_rw_list"\n','') if res.indexOf('"jsn_split_rw_list"') is 0
  return res

API.convert.json2keys = (content, opts={}) ->
  opts.flat = false
  keys = []
  _extract = (content,key) ->
    if _.isArray content
      _extract(c,key) for c in content
    else if typeof content is 'object'
      for c of content
        key = if opts.flat and key then key + '.' + c else c
        kl = if opts.lowercase then key.toLowerCase() else key
        keys.push(kl) if kl not in keys
        _extract(content[c],key)
  _extract content
  return keys

API.convert.json2txt = (content, opts={}) ->
  opts.unique ?= false
  opts.list ?= false
  opts.keys ?= false # means only occurrences of key strings in the text values - still would not include the actual keys
  opts.lowercase = true # only means matches on lowercase, still provides strings as found
  keys = if not opts.keys then API.convert.json2keys(content, opts) else []
  strings = []
  lstrings = []
  _extract = (content) ->
    if _.isArray content
      _extract(c) for c in content
    else if typeof content is 'object'
      _extract(content[c]) for c of content
    else if content
      try
        cl = content.toLowerCase()
      catch
        cl = content
      if opts.numbers isnt false or isNaN(parseInt(content))
        strings.push(content) if (opts.keys or content not in keys) and (not opts.unique or content not in strings) and (not opts.lowercase or cl not in lstrings)
        lstrings.push(cl) if cl not in lstrings
  _extract content
  return if opts.list then strings else strings.join(' ')

# this does not really belong as a convert function, 
# but it seems to have no better place. It is used in aestivus to wrap .csv routes, but may also be useful direclty 
# on other custom written routes, so keep it here
API.convert.json2csv2response = (ths, data, filename) ->
  rows = []
  for dr in (if data?.hits?.hits? then data.hits.hits else data)
    if typeof dr isnt 'object'
      rows.push dr
    else
      rw = if dr._source? then dr._source else if dr.fields then dr.fields else dr
      for k of rw
        rw[k] = rw[k][0] if _.isArray(rw[k]) and rw[k].length is 1
      rows.push rw
  csv = API.convert.json2csv rows, {fields:ths.queryParams?.fields ? ths.bodyParams?.fields}
  API.convert.csv2response ths, csv, filename

API.convert.csv2response = (ths, csv, filename) ->
  filename ?= 'export_' + moment(Date.now(), "x").format("YYYY_MM_DD_HHmm_ss") + ".csv"
  ths.response.writeHead(200, {'Content-disposition': "attachment; filename=" + filename, 'Content-type': 'text/csv; charset=UTF-8', 'Content-Encoding': 'UTF-8'})
  ths.response.end csv

API.convert.json2json = (content, opts) ->
  content = HTTP.call('GET', content).content if content.indexOf('http') is 0
  content = JSON.parse(content) if typeof content is 'string'
  if opts.subset
    parts = opts.subset.split('.')
    n = {}
    n[s] = content[s] for s in parts
    content = n
  if opts.fields
    recs = []
    for r in content
      rec = {}
      rec[f] = r[f] for f in opts.fields
      recs.push rec
    content = recs
  return content

API.convert.list2string = (content, opts={}) ->
  opts.newline ?= '\n'
  opts.join ?= ', '
  st = ''
  try
    content = HTTP.call('GET', content).content if content.indexOf('http') is 0
    content = API.convert.xml2json(content) if typeof content is 'string' and content.indexOf('<') is 0
    content = API.convert.json2json(content,opts) if opts.subset? or opts.fields?
    content = content[opts.subset] if opts.subset?
    for row in content
      st += opts.newline if st isnt ''
      if typeof row is 'string'
        st += row
      else
        opts.order ?= _.keys row
        opts.order = opts.order.split(',') if typeof opts.order is 'string'
        first = true
        for o in opts.order
          if row[o]?
            if first
              first = false
            else
              st += opts.join
            if typeof row[o] is 'string'
              dt = row[o]
            else
              # can't easily specify this easily and deeply enough via params, but Joe wanted affiliation data out of unpaywall 
              # which provides affiliation as a list of objects, each of which has at least a key called name. So make some assumptions
              dt = ''
              ob = if _.isArray(row[o]) then row[o] else [row[o]]
              for rw in ob
                dt += opts.join if dt isnt ''
                if typeof rw is 'string'
                  dt += rw
                else
                  for k of rw
                    dt += (if opts.keys then k + ': ' else '') + rw[k]
            st += (if opts.keys then o + ': ' else '') + dt
  return if opts.json then {text: st} else st

API.convert._hexMatch = 
  '0': '0000',
  '1': '0001',
  '2': '0010',
  '3': '0011',
  '4': '0100',
  '5': '0101',
  '6': '0110',
  '7': '0111',
  '8': '1000',
  '9': '1001',
  'a': '1010',
  'b': '1011',
  'c': '1100',
  'd': '1101',
  'e': '1110',
  'f': '1111'

API.convert.hex2binary = (ls,listed=false) ->
  ls = [ls] if not _.isArray ls
  res = []
  for l in ls
    res.push API.convert._hexMatch[l.toLowerCase()]
  return if listed then res else res.join('')

API.convert.binary2hex = (ls) ->
  # this needs work...
  if not _.isArray ls
    els = []
    sls = ls.split('')
    pr = ''
    while sls.length
      pr += sls.shift()
      if pr.length is 4
        els.push pr
        pr = ''
    ls = els
  res = []
  hm = {}
  for k of API.convert._hexMatch
    hm[API.convert._hexMatch[k]] = k
  for l in ls
    res.push '0x' + hm[l]
  return new Buffer(res).toString()
  
API.convert.buffer2binary = (buf) ->
  buf = buf.toString('hex') if Buffer.isBuffer buf
  buf = buf.replace /^0x/, ''
  #assert(/^[0-9a-fA-F]+$/.test(s))
  ret = ''
  c = 0
  while c < buf.length
    ret += API.convert.hex2binary buf[c]
    c++
  return ret
  
  

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