
import jimp from 'jimp'
import { Random } from 'meteor/random'

# https://www.npmjs.com/package/jimp

API.add 'img',
  get: () ->
    if this.queryParams.url? or this.queryParams.fn?
      if this.queryParams.data?
        return API.img this.queryParams
      else
        this.response.writeHead 200
        this.response.end API.img this.queryParams
        this.done()
    else
      return {} # return what? A listing of all images? A search of images?

API.add 'img/:fn', # is it worth sub-routing this like the ES function?
  get: () ->
    # given an image filename, return the image as an image
    # if passed params for the image, get the saved image that matches those params
    # if image that matches params does not exist yet, make it, save it, then return it
    this.queryParams.fn = this.urlParams.fn
    this.response.writeHead 200
    this.response.end API.img this.queryParams
    this.done()
  post: () ->
    authOptional: true
    action: () ->
      this.bodyParams.fn = this.urlParams.fn
      return API.img this.bodyParams



API.img = (opts={}) ->
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
  if opts.url? or opts.img?
    # this would create a new one every time with slightly different names, never re-using
    opts.fn ?= 'img/' + if opts.url then opts.url.split('/').pop() else Random.id() + '.png' # or better to use full url as fn? but made disk safe?
    if not API.store.exists opts.fn
      saved = API.store.create opts.fn, true, undefined, opts.url ? opts.img
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
  pfn = fnparts.join('.') + '__'
  alter = false
  for k in keys
    if k not in ['url','img','fn','color','apikey','data','position']
      alter = true
      pfn += '_' + k + '__' + if typeof opts[k] is 'object' then JSON.stringify(opts[k]) else opts[k]
  pfn += '.' + suffix

  if not alter and saved? and not opts.data?
    return API.store.retrieve opts.fn
  else if not opts.data? and API.store.exists pfn
    return API.store.retrieve pfn
  else if opts.data? and API.store.exists pfn
    return (Async.wrap (callback) ->
      jimp.read API.store.retrieve(pfn), (err, img) ->
        img.greyscale().contrast(1) if opts.position? and opts.clusters is 2
        mdt = API.img._data img, (if opts.clusters? then parseInt(opts.clusters) else undefined), opts.position? and opts.clusters is 2
        if opts.clusters isnt 2 and opts.position?
          img.greyscale().contrast(1)
          mdp = API.img._data img, 2, true
          mdt.focus = mdp.focus
        return callback null, mdt)()
  else
    #try
    # prob need to wrap this in async with a callback to return
    _process = Async.wrap (callback) ->
      jimp.read API.store.retrieve(opts.fn), (err, img) ->
        return callback(err,undefined) if err
        if opts.x? and opts.y? and opts.w? and opts.h?
          try img.crop parseInt(opts.x), parseInt(opts.y), parseInt(opts.w), parseInt(opts.h)
        else if opts.w? or opts.h?
          action = if opts.contain then 'contain' else (if opts.cover then 'cover' else (if opts.scaleToFit then 'scaleToFit' else 'resize'))
          try img[action] (if opts.w? then parseInt(opts.w) else jimp.AUTO), (if opts.h? then parseInt(opts.h) else jimp.AUTO)
        for vact in ['scaleToFit', 'quality', 'rotate', 'brightness', 'contrast', 'fade', 'opacity', 'gaussian', 'blur', 'posterize', 'pixelate']
          # scale is scale factor number, quality is 0-100, rotate is 0-360, brightness or contrast are -1 to 1, fade or opacity are 0 to 1 (will only work on png)
          # gaussian (will be slow) or blur are values of pixel blur, posterize is a level number, pixelate is a pixel size
          if opts[vact]? and (vact isnt 'scaleToFit' or opts.scaleToFit isnt true)
            opts[vact] = 3 if vact in ['blur','pixelate'] and opts[vact] is "true"
            opts[vact] = 20 if vact is 'posterize' and opts[vact] is "true"
            try img[vact] (1000*opts[vact])/1000
        for act in ['dither565', 'invert', 'normalize', 'opaque', 'sepia', 'greyscale']
          if opts[act]?
            try img[act]()
        if opts.flip?
          try img.flip opts.flip.indexOf('horizontal') isnt -1, opts.flip.indexOf('vertical') isnt -1
        if opts.convolute?
          if typeof opts.convolute is 'string'
            cvs = opts.convolute.split(',')
            #opts.convolute = [[cvs[0],cvs[1],cvs[2]],[cvs[3],cvs[4],cvs[5]],[cvs[6],cvs[7],cvs[8]]]
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
          img.convolute opts.convolute
        if opts.emboss?
          img.convolute([
            [-2,-1, 0],
            [-1, 1, 1],
            [ 0, 1, 2]
          ])
        if opts.edge?
          img.convolute([
            [0,1,0],
            [1,-4,1],
            [0,1,0]
          ])
        if opts.softedge?
          img.convolute([
            [0,0,0],
            [1,1,0],
            [0,0,0]
          ])
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
          try img.color opts.color

        # displace might provide some cool 3d effects, work with maps etc?
        # other more useful stuff in creating new images, perception hashes for image (or any file) comparison,
        # low level manipulation or analysis of particular parts of images
        # also there are resize modes and alignment settings for where to align in cropping to cover, etc

        if opts.focuscrop?
          img2 = img.clone()
          img2.greyscale().contrast(1)
          img2.resize(100, jimp.AUTO) if img2.bitmap.width > 100
          if img2.bitmap.width > 100 or img2.bitmap.height > 100
            img2.resize (if img2.bitmap.width > 100 then 100 else jimp.AUTO), (if img2.bitmap.height > 100 then 100 else jimp.AUTO)
          data = API.img._data img2, 2, true
          halved = 1
          if data.focus.lightness >= 48 and data.focus.lightness <= 52 and data.colours[0].py >= 20 and data.colours[0].py <= 30 and data.colours[1].py >= 70 and data.colours[1].py <= 80
            # find images with stark top and bottom areas, where centre of colour mass is also very clear
            # such as wide landscape shots with half horizon, and small focal point above or around the horizon line
            halved = 2-((-50+data.focus.lightness)/4)
            img2.crop 0, 0, img2.bitmap.width, Math.floor(img2.bitmap.height/halved)
            img3 = (Async.wrap (callback) ->
              img2.getBuffer jimp.AUTO, (err, res) ->
                jimp.read res, (err, img) ->
                  return callback null, img)()
            data = API.img._data img3, 2, true
            '''if data.focus.pc < 10
              imgA = img3.clone()
              imgA.crop 0, 0, Math.floor(imgA.bitmap.width/2), imgA.bitmap.height
              img4 = (Async.wrap (callback) ->
                imgA.getBuffer jimp.AUTO, (err, res) ->
                  jimp.read res, (err, img) ->
                    return callback null, img)()
              Adata = API.img._data img4, 2, true
              imgB = img3.clone()
              imgB.crop Math.floor(imgB.bitmap.width/2), 0, Math.floor(imgB.bitmap.width/2), imgB.bitmap.height
              img5 = (Async.wrap (callback) ->
                imgB.getBuffer jimp.AUTO, (err, res) ->
                  jimp.read res, (err, img) ->
                    return callback null, img)()
              Bdata = API.img._data img5, 2, true
              data = if Adata.focus.lightness < Bdata.focus.lightness then Adata else Bdata'''
          img.crop Math.floor((data.focus.bx/100)*img.bitmap.width), Math.floor(((data.focus.by/100)*img.bitmap.height)/halved), Math.floor((data.focus.bw/100)*img.bitmap.width), Math.floor(((data.focus.bh/100)*img.bitmap.height)/halved)

        if opts.preload? # make the image small for fast loads
          img.resize((if img.bitmap.width > img.bitmap.height then 200 else jimp.AUTO),(if img.bitmap.height > img.bitmap.width then 200 else jimp.AUTO))
          img.greyscale()
          img.blur(3)

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
            jimp.read API.store.retrieve(which), (err, mask) ->
              mask.resize((if opts.mw? then parseInt(opts.mw) else (if opts.w? then parseInt(opts.w) else jimp.AUTO)), (if opts.mh? then parseInt(opts.mh) else (if opts.h? then parseInt(opts.h) else jimp.AUTO))) if opts.w? or opts.h?
              mcolor = opts.mcolor ? []
              for mact in ['mred','mgreen','mblue']
                if opts[mact]?
                  mcolor.push({apply:mact.replace('m',''), params: [opts[mact]]})
              mask.color(mcolor) if mcolor.length
              img[if opts.mask? then 'mask' else 'composite'] mask, (if opts.x then parseInt(opts.x) else 0), (if opts.y then parseInt(opts.y) else 0)
              img.getBuffer jimp.AUTO, (err, res) ->
                saved = API.store.create pfn, true, undefined, res
                if opts.data?
                  return callback null, API.img._data(img, (if opts.clusters? then parseInt(opts.clusters) else undefined), opts.position?)
                else
                  return callback null, res #API.store.retrieve pfn

        # could also img.write(pfn) or img.getBase64( mime, cb ) if necessary
        img.getBuffer jimp.AUTO, (err, res) ->
          return callback(err,undefined) if err
          saved = API.store.create pfn, true, undefined, res
          if opts.data?
            return callback null, API.img._data(img, (if opts.clusters? then parseInt(opts.clusters) else undefined), opts.position?)
          else
            return callback null, res #API.store.retrieve pfn

    # return the image? or just the location on disk?
    return _process()
    #catch
    #  return undefined



API.img._data = (img,clusters=5,position=false) ->
  if img.bitmap.width > 120 or img.bitmap.height > 120
    img = img.clone()
    img.resize (if img.bitmap.width > 120 then 120 else jimp.AUTO), (if img.bitmap.height > 120 then 120 else jimp.AUTO)

  _scan = Async.wrap (callback) ->
    info = {
      avg: {
        red: 0,
        green: 0,
        blue: 0,
        alpha: 0
      }
    }
    vector = []
    img.scan 0, 0, img.bitmap.width, img.bitmap.height, (x, y, idx) ->
      red = this.bitmap.data[ idx + 0 ]
      green = this.bitmap.data[ idx + 1 ]
      blue = this.bitmap.data[ idx + 2 ]
      alpha = this.bitmap.data[ idx + 3 ]

      vc = [red,green,blue]
      if position
        vc.push x
        vc.push y
      vector.push vc

      info.avg.red += red
      info.avg.green += green
      info.avg.blue += blue
      info.avg.alpha += alpha

      if x is this.bitmap.width-1 and y is this.bitmap.height-1
        info.avg.red = Math.floor(info.avg.red / (this.bitmap.data.length / 4))
        info.avg.green = Math.floor(info.avg.green / (this.bitmap.data.length / 4))
        info.avg.blue = Math.floor(info.avg.blue / (this.bitmap.data.length / 4))
        info.avg.alpha = Math.floor(info.avg.alpha / (this.bitmap.data.length / 4))
        info.avg.hex = '#' + info.avg.red.toString(16) + info.avg.green.toString(16) + info.avg.blue.toString(16)
        info.colours = []
        info.clusters = API.tdm.kmeans vector, clusters
        delete info.clusters.cluster
        total = 0
        total += sz for sz in info.clusters.sizes
        for c of info.clusters.centroids
          hex = '#'
          for cv of info.clusters.centroids[c]
            info.clusters.centroids[c][cv] = Math.floor info.clusters.centroids[c][cv]
            hex += info.clusters.centroids[c][cv].toString(16) if cv isnt "3" and cv isnt "4"
          col = {hex: hex, pc: Math.floor((info.clusters.sizes[c]/total)*100)}
          if position
            try
              col.px = Math.floor (info.clusters.centroids[c][3]/this.bitmap.width)*100
              col.py = Math.floor (info.clusters.centroids[c][4]/this.bitmap.height)*100
          info.colours.push col
        if position and clusters is 2
          lightness = Math.floor(((info.avg.red + info.avg.green + info.avg.blue)/765)*100)
          darker = info.avg.red + info.avg.green + info.avg.blue < 383
          if info.clusters.centroids[0][0] + info.clusters.centroids[0][1] + info.clusters.centroids[0][2] < info.clusters.centroids[1][0] + info.clusters.centroids[1][1] + info.clusters.centroids[1][2]
            which = if darker then info.colours[1] else info.colours[0]
          else
            which = if darker then info.colours[0] else info.colours[1]
          info.focus = {px:which.px,py:which.py,pc:which.pc,darker:darker,lightness:lightness,landscape:this.bitmap.width > this.bitmap.height}
          xmod = (if info.focus.pc < 17 then 17 else info.focus.pc) * 1.15 * if not info.focus.landscape then 2 else 1
          ymod = (if info.focus.pc < 17 then 17 else info.focus.pc) * 1.15 * if info.focus.landscape then 2 else 1
          info.focus.bx = if info.focus.px - xmod < 0 then 0 else Math.floor info.focus.px - xmod
          info.focus.by = if info.focus.py - ymod < 0 then 0 else Math.floor info.focus.py - ymod
          info.focus.bw = if xmod * 2 > 100 - info.focus.bx then 100 - info.focus.bx else Math.floor xmod * 2
          info.focus.bh = if ymod * 2 > 100 - info.focus.by then 100 - info.focus.by else Math.floor ymod * 2
          if info.focus.pc > 35 and (Math.abs(info.colours[0].py - info.colours[1].py) < 10 or Math.abs(info.colours[0].px - info.colours[1].px) < 10)
            info.focus.by = Math.floor info.focus.by/2 # reduce by height when it seems the focus may be central, e.g. like a selfie
        delete info.clusters
        console.log info
        return callback null, info

  return _scan()


