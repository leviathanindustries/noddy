
import Future from 'fibers/future'
import request from 'request'
import fs from 'fs'
import stream from 'stream'
import eventStream from 'event-stream'
import iconvLite from 'iconv-lite'



API.streamer = (filename, batch, wait=true, begin, end, record, done, batchSize=1000, format) ->
  this.filename = filename
  this.batch = batch
  this.wait = wait
  this.begin = begin
  this.end = end
  this.record = record
  this.done = done
  this.batchSize = batchSize
  if typeof filename is 'string'
    this.format = format ? filename.toLowerCase().split('.')[1]
  if this.format is 'json'
    this.begin ?= '{'
    this.end ?= '}'
  else if this.format is 'xml'
    this.begin ?= '<' # this would really not be much use, for xml almost certainly need to know what objects starting tags to scrape
    this.end ?= '</'
  else if this.format is 'csv'
    # would also need a way to get the top row for key names first
    this.begin = ''
    this.end = ''
  # filename could already be a stream here
  # but what if it is text content? e.g. a large xml or json already read in?
  # would not be very useful to send such a thing to a stream reader as it is already in memory, but still may have to consider what to do in that scenario... TODO
  this.reader = (if typeof filename isnt 'string' then filename else if filename.indexOf('http') is 0 then request(filename) else fs.createReadStream(filename)).pipe(iconvLite.decodeStream('utf8'))
  this.lineNumber = 0
  this.recordNumber = 0
  this.cache = ''
  this.caching = false
  this.nesting = 0
  this.records = []

API.streamer.prototype._begin = (line) ->
  if typeof this.begin is 'function'
    return this.begin line
  else
    line = line.replace(',','') if this.begin is '{' and line.indexOf(',') isnt -1 and line.indexOf(',') < line.indexOf('{')
    return if line.replace(/ /g,'').indexOf(this.begin) is 0 then line else false

API.streamer.prototype._end = (line) ->
  if typeof this.end is 'function'
    return this.end line
  else
    return if line.replace(/ /g,'').indexOf(this.end) is 0 then (if this.nesting-1 is 0 then '}' else line) else false

API.streamer.prototype._record = (record) ->
  if typeof this.record is 'function'
    return this.record record
  else if this.format is 'json'
    return JSON.parse record
  else if this.format is 'xml'
    return API.convert.xml2json record
  else if this.format is 'csv'
    console.log 'Do csv by first getting the keys from the file top, or from provided by user. then make an obj with them'

API.streamer.prototype._batch ?= (records) ->
  console.log records.length
  console.log typeof records[0] if records.length

API.streamer.prototype._done = () ->
  if typeof this.done is 'function'
    return this.done()
  else
    console.log 'Ended function run'

API.streamer.prototype._read = () ->
  this.reader
    .pipe(eventStream.split())
    .pipe(eventStream.mapSync (line) ->
      ++this.lineNumber
      console.log this.lineNumber
      
      if b = this._begin(line)
        this.cache += (if this.nesting then line else b) if b isnt true or this.caching
        this.nesting += 1
        this.caching = true
      else if e = this._end(line)
        this.nesting -= 1
        this.cache += (if this.nesting then line else e) if e isnt true
        if this.nesting is 0
          this.records.push this._record(this.cache)
          this.cache = ''
          this.caching = false
          ++this.recordNumber
          if this.recordNumber % this.batchSize is 0
            this._batch this.records
            this.records = []
      else if this.caching
        this.cache += line
    )
    .on('error', () -> console.log 'Error in streamer around line ' + this.lineNumber + ' or record ' + this.recordNumber)
    .on('end', () -> 
      if this.cache
        try
          this.records.push this._record(this.cache)
          this.cache = ''
          this.caching = false
          ++this.recordNumber
      if this.records
        try
          this._batch(this.records)
          this.records = []
      console.log 'Streamer read ' + this.lineNumber + ' lines and processed ' + this.recordNumber + ' records'
      _done()
    )

API.streamer.prototype.read = (_batch, _begin, _end, _record, _done) ->
  done = false
  _done ?= () ->
    done = true
  API.streamer.prototype._read _batch, _begin, _end, _record, _done
  if this.wait
    while done is false
      future = new Future()
      Meteor.setTimeout (() -> future.return()), 500
      future.wait()
  return true
  
'''
API.streamer.prototype.continue = () ->
  this.data = []
  this.reader.resume()
'''

API.add 'streamer/test',
  get: () ->
    results = []
    #streamer = new API.streamer '/home/cloo/nims-ngdr-development-2018/Metadata/Pubman/pubman_metadata/escidoc_dump_nnin.xml', ((records) -> results.push(record) for r in records), true, '<item ', '</item'
    #streamer.read()
    console.log results.length
    return results
