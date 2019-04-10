
# https://www.npmjs.com/package/jimp

import jimp from 'jimp'
import { Random } from 'meteor/random'

import phash from 'phash-image'

import fs from 'fs'

# phash below require phash and other things installed
# sudo apt-get install cimg-dev libphash0-dev libmagickcore-dev
# read more about perceptual hash at phash.org

API.add 'img',
  get: () ->
    if this.queryParams.url? or this.queryParams.fn?
      if this.queryParams.data?
        return API.img.jimp this.queryParams
      else
        this.response.writeHead 200
        this.response.end API.img.jimp this.queryParams
    else
      return {} # return what? A listing of all images? A search of images?

API.add 'img/phash', get: () -> return API.img.phash this.queryParams.url
#API.add 'img/phash', post: () -> return API.img.phash this.request.body # should probably be a file save and read first

API.add 'img/phash/difference', get: () -> return API.img.difference this.queryParams.a, this.queryParams.b, not this.queryParams.simple?

API.add 'img/pdf', get: () -> return API.img.pdf this.queryParams.url

API.add 'img/:fn', # is it worth sub-routing this like the ES function?
  get: () ->
    # given an image filename, return the image as an image
    # if passed params for the image, get the saved image that matches those params
    # if image that matches params does not exist yet, make it, save it, then return it
    this.queryParams.fn = this.urlParams.fn
    this.response.writeHead 200
    this.response.end API.img.jimp this.queryParams
  post: () ->
    authOptional: true
    action: () ->
      this.bodyParams.fn = this.urlParams.fn
      this.bodyParams.data = true
      return API.img.jimp this.bodyParams


API.img = {}

API.img.pdf = (fn) ->
  fn ?= '/home/cloo/pubman/pdfs/1015547/effects_of_particle_size_on_cell_function_and_morphology_01_OCR.pdf'
  fn = fs.readFileSync(fn) if fn.indexOf('http') isnt 0 and fn.length < 100
  res = API.convert.pdf2json fn
  return res
  
API.img.phash = (fn, binary=true, buffer=false, int=false, mh=false) ->
  checksum = API.job.sign(fn).replace(/\//g,'_')
	#exists = API.http.cache checksum, 'img_phash'
	#return exists if exists

  if fn.indexOf('http://') is 0 or (fn.indexOf('/') isnt 0 and typeof fn is 'string' and fn.length > 30)
    if not fs.existsSync '/tmp/'+checksum
      content = if fn.indexOf('http://') is 0 then HTTP.call('GET',fn,{npmRequestOptions:{encoding:null}}).content else fn
      fs.writeFileSync '/tmp/'+checksum, content
    fn = '/tmp/'+checksum
  # probably should try caching the result too
  # given the image somehow, work out the phash for it
  # https://www.npmjs.com/package/phash-image
  _phash = Async.wrap (fn, callback) ->
    if mh
      phash.mh fn, (err,hash) -> callback null, (if binary then API.convert.buffer2binary(hash) else if buffer then hash else hash.toString())
    else if int
      phash fn, true, (err,hash) -> callback null, hash
    else
      phash fn, (err,hash) -> callback null, (if binary then API.convert.buffer2binary(hash) else if buffer then hash else hash.toString())
  res = _phash fn
  #API.http.cache(checksum, 'img_phash', res) if res
  return res

API.img.difference = (a,b,simple=true,algo) ->
  algo = algo.split(',') if typeof algo is 'string'
  algo ?= ['hamming','levenshtein'] if not simple
  algo ?= ['hamming']
  #checksum = API.job.sign a, b
	#exists = API.http.cache checksum, 'img_difference'
	#return exists if exists
  res = {}
  res.a = API.img.phash a
  res.b = API.img.phash b
  for a in algo
    res[a] = API.tdm[a] res.a, res.b
  #API.http.cache checksum, 'img_difference', res
  return if simple and algo.length is 1 then res.hamming else res

API.img.jimp = (opts={}) ->
  # tidy some possible provided values
  if opts.vignette?
    opts.composite = 'vignette.png'
    delete opts.vignette
  if opts.q?
    opts.quality = opts.q
    delete opts.q
  if opts.bg?
    opts.background = opts.bg
    delete opts.bg
  if opts.background? and (opts.background.indexOf('#') is 0 or opts.background.length is 6)
    opts.background = '#' + opts.background.replace('#','') # or convert from html color code to hex code format 0xFFFFFFFF
  if opts.f?
    opts.scale = opts.f
    delete opts.f
  if opts.posterise?
    opts.posterize = opts.posterise
    delete opts.posterise
  if opts.scale?
    opts.scaleToFit = opts.scale
    delete opts.scale
  if opts.dither?
    opts.dither565 = opts.dither
    delete opts.dither
  if opts.normalise?
    opts.normalize = opts.normalise
    delete opts.normalise
  if opts.colour?
    opts.color = opts.colour
    delete opts.colour
  if opts.fn? and opts.fn.indexOf('img/') isnt 0
    opts.fn = 'img/' + opts.fn

  saved = false
  if opts.url?
    # this would create a new one every time with slightly different names, never re-using
    opts.fn ?= 'img/' + if opts.url then opts.url.split('/').pop() else Random.id() + '.png' # or better to use full url as fn? but made disk safe?
    if not API.store.exists opts.fn
      saved = API.store.create opts.fn, true, undefined, opts.url
      opts.fn = saved.path
    else
      saved = true

  # convert any svg to png - NOTE this means requests for svg will actually return png
  if opts.url? and opts.url.toLowerCase().indexOf('.svg') isnt -1
    opts.fn = opts.fn.replace('.SVG','.png').replace('.svg','.png')
    if not API.store.exists opts.fn
      saved = API.store.create opts.fn, true, undefined, API.convert.svg2png(opts.url)
      opts.fn = saved.path
    else
      saved = true

  # work out a value to represent this filename with changes applied, not including url or img params
  if opts.fn? and opts.fn.indexOf('img/') is -1
    opts.fn = 'img/' + opts.fn
  keys = _.keys opts
  keys.sort()
  fnparts = opts.fn.split('.')
  suffix = fnparts.pop().toLowerCase()
  suffix = 'png' if suffix not in ['png','jpg','jpeg']
  pfn = fnparts.join('.')
  alter = false
  for k in keys
    ignores = ['url','fn','apikey','data','clusters']
    ignores.push('focuscrop') if 'data' in keys
    if k not in ignores
      alter = true
      pfn += '_' + k + '__' + if typeof opts[k] is 'object' then JSON.stringify(opts[k]) else opts[k]
  pfn += '.' + suffix

  if not alter and saved? and not opts.data?
    return API.store.retrieve opts.fn
  else if not opts.data? and API.store.exists pfn
    return API.store.retrieve pfn
  else if opts.data? and API.store.exists pfn
    img = (Async.wrap (callback) ->
      jimp.read API.store.retrieve(pfn), (err, img) ->
        return callback null, img)()
    data = API.img._data pfn, img, (if opts.clusters? then parseInt(opts.clusters) else undefined), opts.focuscrop?, (if opts.phash then opts.url else undefined)
    data.fn = opts.fn
    data.width = img.bitmap.width
    data.height = img.bitmap.height
    return data
  else
    jimg = (Async.wrap (callback) ->
      jimp.read API.store.retrieve(opts.fn), (err, img) ->
        return callback null, img)()

    if opts.x? and opts.y? and opts.w? and opts.h?
      try jimg.crop parseInt(opts.x), parseInt(opts.y), parseInt(opts.w), parseInt(opts.h)
    else if opts.w? or opts.h?
      action = if opts.contain then 'contain' else (if opts.cover then 'cover' else (if opts.scaleToFit then 'scaleToFit' else 'resize'))
      try jimg[action] (if opts.w? then parseInt(opts.w) else jimp.AUTO), (if opts.h? then parseInt(opts.h) else jimp.AUTO)

    for vact in ['scaleToFit', 'quality', 'rotate', 'brightness', 'contrast', 'fade', 'opacity', 'gaussian', 'blur', 'posterize', 'pixelate']
      # scale is scale factor number, quality is 0-100, rotate is 0-360, brightness or contrast are -1 to 1, fade or opacity are 0 to 1 (will only work on png)
      # gaussian (will be slow) or blur are values of pixel blur, posterize is a level number, pixelate is a pixel size
      if opts[vact]? and (vact isnt 'scaleToFit' or opts.scaleToFit isnt true)
        opts[vact] = 3 if vact in ['blur','pixelate'] and opts[vact] is "true"
        opts[vact] = 20 if vact is 'posterize' and opts[vact] is "true"
        try jimg[vact] (1000*opts[vact])/1000

    for act in ['dither565', 'invert', 'normalize', 'opaque', 'sepia', 'greyscale']
      if opts[act]?
        try jimg[act]()

    if opts.flip?
      try jimg.flip opts.flip.indexOf('horizontal') isnt -1, opts.flip.indexOf('vertical') isnt -1

    if opts.convolute?
      if typeof opts.convolute is 'string'
        cvs = opts.convolute.split(',')
        rows = Math.sqrt(cvs.length)
        opts.convolute = [[]]
        row = 0
        counter = 0
        for c in cvs
          opts.convolute[row.toString()].push c
          counter += 1
          if counter is rows
            opts.convolute.push([]) if opts.convolute.length isnt rows
            counter = 0
            row += 1
      try jimg.convolute opts.convolute
    if opts.emboss?
      try jimg.convolute [ [-2,-1, 0], [-1, 1, 1], [ 0, 1, 2] ]
    if opts.edge?
      try jimg.convolute [ [0,1,0], [1,-4,1], [0,1,0] ]
    if opts.softedge?
      try jimg.convolute [ [0,0,0], [1,1,0], [0,0,0] ]

    for cact in ['desaturate','saturate','greyscale','spin','mix','xor','red','green','blue']
      # desaturate 0 to 100 - 100 is greyscale
      # saturate 0 to 100
      # greyscale {amount} ?
      # spin -360 to 360 - spin hue
      # mix {color, amount}	Mixes colors by their RGB component values. Amount is opacity (0 to 100) of overlaying color (tint is mix with white, shade is mix with black)
      # xor {color}	Treats the two colors as bitfields and applies an XOR operation to the red, green, and blue components
      # red {amount}	Modify Red component by a given amount (0 to 255)
      # green {amount}	Modify Green component by a given amount
      # blue {amount}	Modify Blue component by a given amount
      if opts[cact]?
        opts.color ?= []
        params = opts[cact].split(',')
        for p of params
          try
            numbered = (1000*params[p])/1000
            if not isNaN numbered
              params[p] = numbered
          try
            #if cact in ['xor','mix'] and p is "0" and params[p].toString().indexOf('0x') isnt 0
            #  params[p] = '0x' + params[p].toString().replace('#','')
            #  params[p] += '00' if params[p].length isnt 10 # is FF always suitable when not known?
            if cact in ['xor','mix'] and p is "0" and params[p].toString().indexOf('#') isnt 0
              params[p] = '#' + params[p].toString()
        opts.color.push({apply:cact, params: params})
    if opts.color?
      try jimg.color opts.color

    # displace might provide some cool 3d effects, work with maps etc?
    # other more useful stuff in creating new images, perception hashes for image (or any file) comparison,
    # low level manipulation or analysis of particular parts of images
    # also there are resize modes and alignment settings for where to align in cropping to cover, etc

    if opts.focuscrop? and not opts.data?
      try
        data = API.img._data pfn, jimg, 0, true
        jimg.crop Math.floor((data.focus.bx/100)*jimg.bitmap.width), Math.floor((data.focus.by/100)*jimg.bitmap.height), Math.floor((data.focus.bw/100)*jimg.bitmap.width), Math.floor((data.focus.bh/100)*jimg.bitmap.height)

    opts.mask = 'img/' + opts.mask if opts.mask? and opts.mask.indexOf('img/') is -1 and opts.mask.indexOf('http') isnt 0
    opts.composite = 'img/' + opts.composite if opts.composite? and opts.composite.indexOf('img/') is -1 and opts.composite.indexOf('http') isnt 0
    if (opts.mask? or opts.composite?) and ((opts.mask? and opts.mask.indexOf('http') is 0) or (opts.composite? and opts.composite.indexOf('http') is 0) or API.store.exists opts.mask ? opts.composite)
      try
        which = opts.mask ? opts.composite
        if which.indexOf('http') is 0
          wfn = which.split('/').pop()
          if not API.store.exists wfn
            msv = API.store.create wfn, true, undefined, which
            which = msv.path
        mask = (Async.wrap (callback) ->
          jimp.read API.store.retrieve(which), (err, mask) ->
            return callback null, mask)()
        mask.resize((if opts.mw? then parseInt(opts.mw) else (if opts.w? then parseInt(opts.w) else jimp.AUTO)), (if opts.mh? then parseInt(opts.mh) else (if opts.h? then parseInt(opts.h) else jimp.AUTO))) if opts.w? or opts.h?
        mcolor = opts.mcolor ? []
        for mact in ['mred','mgreen','mblue']
          if opts[mact]?
            mcolor.push({apply:mact.replace('m',''), params: [opts[mact]]})
        mask.color(mcolor) if mcolor.length
        jimg[if opts.mask? then 'mask' else 'composite'] mask, (if opts.x then parseInt(opts.x) else 0), (if opts.y then parseInt(opts.y) else 0)

    if opts.preload? # make the image small for fast loads
      try
        jimg.resize((if jimg.bitmap.width > jimg.bitmap.height then 200 else jimp.AUTO),(if jimg.bitmap.height > jimg.bitmap.width then 200 else jimp.AUTO))
        jimg.greyscale()
        jimg.blur(3)

    # could also img.write(pfn) or img.getBase64( mime, cb ) if necessary
    bimg = (Async.wrap (callback) ->
      jimg.getBuffer jimp.AUTO, (err, res) ->
        return callback null, res)()
    saved = API.store.create pfn, true, undefined, bimg
    if opts.data?
      data = API.img._data pfn, jimg, (if opts.clusters? then parseInt(opts.clusters) else undefined), opts.focuscrop?, (if opts.phash? then opts.url else undefined)
      data.fn = opts.fn
      data.width = jimg.bitmap.width
      data.height = jimg.bitmap.height
      return data
    else
      return bimg



API.img._data = (pfn, img, clusters=6, focuscrop=false, phash=false) ->
  if pfn
    pfn += '_' + clusters
    pfn += '_focuscrop' if focuscrop
    pfn += '_phashstr' if phash
    exists = API.http.cache pfn, 'img_data'
    return exists if exists?

  if pfn and not img?
    img = (Async.wrap (callback) ->
      jimp.read API.store.retrieve(pfn), (err, img) ->
        return callback null, img)()
  else if img?
    img = (Async.wrap (callback) ->
      img.getBuffer jimp.AUTO, (err, res) ->
        jimp.read res, (err, img) ->
          return callback null, img)()

  return {} if not img?

  if img.bitmap.width > 100 or img.bitmap.height > 100
    img.resize (if img.bitmap.width >= img.bitmap.height then 100 else jimp.AUTO), (if img.bitmap.height >= img.bitmap.width then 100 else jimp.AUTO)

  info = {
    avg: {
      red: 0,
      green: 0,
      blue: 0,
      alpha: 0
    },
    colours: [],
    landscape: img.bitmap.width > img.bitmap.height
  }
  foci = []
  vector = []

  if focuscrop
    gimg = img.clone()
    gimg.greyscale().contrast(1)
    
  if phash
    try info.phash = API.img.phash phash
    try info.phashstr = API.img.phash phash, false

  img.scan 0, 0, img.bitmap.width, img.bitmap.height, (x, y, idx) ->
    info.avg.red += img.bitmap.data[idx]
    info.avg.green += img.bitmap.data[idx+1]
    info.avg.blue += img.bitmap.data[idx+2]
    #info.avg.alpha += img.bitmap.data[idx+3] # not using the alpha for anything yet

    vector.push [ img.bitmap.data[idx], img.bitmap.data[idx+1], img.bitmap.data[idx+2] ]
    foci.push( [gimg.bitmap.data[idx]+gimg.bitmap.data[idx+1]+gimg.bitmap.data[idx+2], x, y] ) if focuscrop

    if x is img.bitmap.width-1 and y is img.bitmap.height-1
      info.avg.red = Math.floor(info.avg.red / (img.bitmap.data.length / 4))
      info.avg.green = Math.floor(info.avg.green / (img.bitmap.data.length / 4))
      info.avg.blue = Math.floor(info.avg.blue / (img.bitmap.data.length / 4))
      info.avg.alpha = Math.floor(info.avg.alpha / (img.bitmap.data.length / 4))
      info.avg.hex = '#' + info.avg.red.toString(16) + info.avg.green.toString(16) + info.avg.blue.toString(16)
      info.lightness = Math.floor(((info.avg.red + info.avg.green + info.avg.blue)/765)*100)
      if clusters > 1
        info.clusters = API.ml.kmeans vector, clusters
        for c in info.clusters
          hex = '#'
          hex += Math.floor(cv).toString(16) for cv in c.centroid
          info.colours.push {hex: hex, pc: Math.floor((c.size/vector.length)*100)}
        delete info.clusters
      if focuscrop
        info.fcolours = []
        info.fclusters = API.ml.kmeans foci, 2
        info.fcolours.push({pc: Math.floor((c.size / foci.length)*100), px: Math.floor((c.centroid[1] / img.bitmap.width)*100), py: Math.floor((c.centroid[2] / img.bitmap.height)*100)}) for c in info.fclusters
        if info.fclusters[0].centroid[0] < info.fclusters[1].centroid[0]
          which = if info.lightness <= 50 then info.fcolours[1] else info.fcolours[0]
        else
          which = if info.lightness <= 50 then info.fcolours[0] else info.fcolours[1]
        info.focus = {px:which.px, py:which.py, pc:which.pc}
        xmod = (if info.focus.pc < 17 then 17 else info.focus.pc) * 1.15 * if not info.landscape then 2 else 1
        ymod = (if info.focus.pc < 17 then 17 else info.focus.pc) * 1.15 * if info.landscape then 2 else 1
        info.focus.bx = if info.focus.px - xmod < 0 then 0 else Math.floor info.focus.px - xmod
        info.focus.by = if info.focus.py - ymod < 0 then 0 else Math.floor info.focus.py - ymod
        info.focus.bw = if xmod * 2 > 100 - info.focus.bx then 100 - info.focus.bx else Math.floor xmod * 2
        info.focus.bh = if ymod * 2 > 100 - info.focus.by then 100 - info.focus.by else Math.floor ymod * 2
        if info.focus.pc > 35 and (Math.abs(info.colours[0].py - info.colours[1].py) < 10 or Math.abs(info.colours[0].px - info.colours[1].px) < 10)
          info.focus.by = Math.floor info.focus.by/2 # reduce by height when it seems the focus may be central, e.g. like a selfie
        if info.lightness >= 48 and info.lightness <= 52 and info.colours[0].py >= 20 and info.colours[0].py <= 30 and info.colours[1].py >= 70 and info.colours[1].py <= 80
          # find images with stark top and bottom areas, where centre of colour mass is also very clear
          # such as wide landscape shots with half horizon, and small focal point above or around the horizon line
          img.crop 0, 0, img.bitmap.width, Math.floor(img.bitmap.height/(2-((-50+info.lightness)/4)))
          info.focus = API.img._data(undefined, img, 0, true).focus
          # could split vert then horizontal and keep going until a focus is found - see old code below for a start
        delete info.fcolours
        delete info.fclusters

  if pfn
    API.http.cache pfn, 'img_data', info
  return info


'''if data.focus.pc < 10
  imgA = img3.clone()
  imgA.crop 0, 0, Math.floor(imgA.bitmap.width/2), imgA.bitmap.height
  img4 = (Async.wrap (callback) ->
    imgA.getBuffer jimp.AUTO, (err, res) ->
      jimp.read res, (err, img) ->
        return callback null, img)()
  Adata = API.img._data undefined, img4, 2, true
  imgB = img3.clone()
  imgB.crop Math.floor(imgB.bitmap.width/2), 0, Math.floor(imgB.bitmap.width/2), imgB.bitmap.height
  img5 = (Async.wrap (callback) ->
    imgB.getBuffer jimp.AUTO, (err, res) ->
      jimp.read res, (err, img) ->
        return callback null, img)()
  Bdata = API.img._data undefined, img5, 2, true
  data = if Adata.lightness < Bdata.lightness then Adata else Bdata'''
