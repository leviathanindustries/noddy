
API.use ?= {}
API.use.flickr = {}

API.add 'use/flickr', get: () -> return API.use.flickr.search this.queryParams



API.use.flickr.search = (params={}) ->
  return {} if not params.tags? and not params.text?
  if not API.settings.use?.flickr?.apikey?
    API.log 'No apikey available to use flickr'
    return { status: 'error', data: 'NO FLICKR API KEY PRESENT!', error: 'NO FLICKR API KEY PRESENT!'}

  # need tags, which can be comma list and will match image tags, or text which will match title, description or tags
  params.license ?= '1,2,4,5,7,8,9,10' # 0 reserved, 1 ccbyncsa, 2 ccbync, 3 ccbyncnd, 4 ccby, 5 ccbysa, 6 ccbynd, 7 no known restriction, 8 US govt, 9 cc0, 10 public domain
  params.content_type ?= '1' # photos. For more see https://www.flickr.com/services/api/flickr.photos.search.html
  params.media ?= 'photos' # can be all or videos too
  params.tag_mode ?= 'all' # can be any
  params.sort ?= 'interestingness-desc' # relevance (there are others, but these are most useful, or if not set defaults to date desc
  params.text = params.text.replace(/ /g,'*') if params.text

  url = 'https://api.flickr.com/services/rest?method=flickr.photos.search&format=json&nojsoncallback=1&api_key=' + API.settings.use.flickr.apikey
  url += '&' + p + '=' + params[p] for p of params
  API.log 'Using flickr for ' + url
  try
    res = HTTP.call 'GET', url
    res = JSON.parse res.content
    resp = total: res.photos.total, data: res.photos.photo
    for p of resp.data
      ph = resp.data[p]
      ph.url = 'https://farm' + ph.farm + '.staticflickr.com/' + ph.server + '/' + ph.id + '_' + ph.secret + '_z.jpg'
    return resp
  catch err
    return {status: 'error', error: err}

# build image URLs for returned pictures:
# https://farm{farm-id}.staticflickr.com/{server-id}/{id}_{secret}_[OPTIONS].jpg
# OPTIONS:
# s	small square 75x75
# q	large square 150x150
# t	thumbnail, 100 on longest side
# m	small, 240 on longest side
# n	small, 320 on longest side
# -	medium, 500 on longest side
# z	medium 640, 640 on longest side
# c	medium 800, 800 on longest side†
# b	large, 1024 on longest side*
# h	large 1600, 1600 on longest side†
# k	large 2048, 2048 on longest side†
# o	original image, either a jpg, gif or png, depending on source format
