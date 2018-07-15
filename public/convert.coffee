
noddy ?= {}
noddy.convert = {}

_conversions = {
  svg: ['png'],
  table: ['json','csv'],
  csv: ['json','text'],
  html: ['text'],
  json: ['csv','text','json'],
  xml: ['text','json'],
  pdf: ['text','json']
}

_converted = false

# have a method to build a UI that provides url box, from and to dropdowns, and fields box, and maybe a content box too?

noddy.convert.run = (url,from,to,fields,content) ->
  #if content, POST it
  $.ajax
    type: if content then 'POST' else 'GET',
    url: noddy.api + '/convert?from=' + from + '&to=' + to + (if fields then ('&fields=' + (if typeof fields is 'string' then fields else fields.join(','))) else '') + '&url=' + encodeURIComponent url
    data: content # how does the data need to be handled to ensure it can be POSTed?
    success: (data) ->
      _converted = data
      # show some kind of success msg on the page - and possibly chain actions?
    error: (data) ->
      console.log data
      # show an error msg