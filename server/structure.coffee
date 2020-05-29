
import fs from 'fs'

API.add 'structure', 
  get: () -> 
    return if this.queryParams.group then API.structure.nodeslinks(undefined,this.queryParams.group) else API.structure.read()

API.add 'structure/method/:method', get: () -> return API.structure.method(this.urlParams.method)
API.add 'structure/methods', get: () -> return API.structure.methods()
API.add 'structure/collections', get: () -> return API.structure.collections()
API.add 'structure/groups', get: () -> return API.structure.groups()
API.add 'structure/nodes', get: () -> return API.structure.nodes()
API.add 'structure/links', get: () -> return API.structure.links()
API.add 'structure/nodeslinks', get: () -> return API.structure.nodeslinks(undefined, this.queryParams.group)



API.structure = {}

API.structure._structured = false
API.structure.read = (src='/home/cloo/dev/noddy/server') ->
  if API.structure._structured is false
    collections = []
    settings = []
    methods = {}
    helpers = {}
    routes = {}
    called = {}
    TODO = {}
    logs = {}
    
    # TODO add in a parse to see if calls are made from within loops, and if so, capture their conditionals if possible

    # TODO parse the API.add URL routes, find which methods they call before the next route definition, 
    # then add the list of routes that calls a method to the method
    
    # TODO once the above is done it could be possible to parse a static site for URLs that call certain methods
    # although this would depend on what domains and other routings were used to route to the underlying API

    method = {}
    _parse = (fn) ->
      incomment = false
      inroute = false
      counter = 0
      fl = fs.readFileSync(fn).toString()
      for l of lns = fl.replace(/\r\n/g,'\n').split '\n'
        counter += 1
        line = lns[l].replace(/\t/g,'  ')
        if JSON.stringify(method) isnt '{}' and (l is '0' or parseInt(l) is lns.length-1 or (line.indexOf('API.') is 0 and line.indexOf('(') isnt -1))
          method.code = method.code.trim() #.replace(/\n/g,'')
          method.checksum = API.job.sign method.code.replace(/\n/g,'')
          #delete method.code
          if method.name.indexOf('API.') is 0
            methods[method.name] = method
          else
            helpers[method.name] = method
          method = {}

        if line.indexOf('API.settings') isnt -1
          stng = 'API.settings' + line.split('API.settings')[1].split(' ')[0].split(')')[0].split('}')[0].split(',')[0].split('.indexOf')[0].replace(/[^a-zA-Z0-9\.\[\]]/g,'').replace(/\.$/,'')
          if stng.split('.').length > 2
            if method.name
              method.settings ?= []
              method.settings.push(stng) if stng not in method.settings
            settings.push(stng) if stng not in settings

        if line.indexOf('API.add') is 0
          inroute = line.split(' ')[1].split(',')[0].replace(/'/g,'').replace(/"/g,'')
          if inroute.split('/').pop() is 'test'
            inroute = false
          else
            routes[inroute] ?= {methods: [], code: '', filename: fn.split('/noddy/')[1], line: counter}

        if line.toLowerCase().indexOf('todo') isnt -1
          TODO[method.name ? 'GENERAL'] ?= []
          TODO[method.name ? 'GENERAL'].push line.split(if line.indexOf('todo') isnt -1 then 'todo' else 'TODO')[1].trim()
        if incomment or not line.length
          if line.indexOf("'''") isnt -1
            incomment = false
        else if line.trim().startsWith('#') or line.trim().startsWith("'''")
          if line.trim().startsWith("'''")
            incomment = true
        else if line.indexOf('new API.collection') isnt -1
          inroute = false
          coll = line.split('new ')[0].split('=')[0].trim().split(' ')[0]
          collections.push(coll) if coll not in collections and coll isnt 'tc' and coll.indexOf('test_') isnt 0 # don't use test collections
        else if (line.indexOf('API.') is 0 or (not line.startsWith(' ') and line.indexOf('=') isnt -1)) and line.indexOf('(') isnt -1 and line.indexOf('.test') is -1 and line.indexOf('API.add') is -1 and line.indexOf('API.settings') isnt 0
          inroute = false
          method = {}
          method.filename = fn.split('/noddy/')[1]
          method.line = counter
          method.lines = 1
          method.secondary = line.indexOf('API.') isnt 0
          method.code = line
          method.name = line.split(' ')[0]
          method.group = if method.name.indexOf('service.') isnt -1 then method.name.split('service.')[1].split('.')[0] else if method.name.indexOf('use.') isnt -1 then method.name.split('use.')[1].split('.')[0] else if method.name.indexOf('API.') is 0 then  method.name.replace('API.','').split('.')[0] else undefined
          method.args = line.split('(')[1].split(')')[0].split(',')
          for a of method.args
            method.args[a] = method.args[a].trim() #.split('=')[0].trim()
          method.calls = []
          method.remotes = []
        else if inroute
          routes[inroute].code += (if routes[inroute].code then '\n' else '') + line
          if line.indexOf('API.') isnt -1 and line.indexOf('.test') is -1 and line.indexOf('API.settings') isnt 0
            rtm = line.replace('API.add','').replace('API.settings','')
            if rtm.indexOf('API.') isnt -1
              rtmc = 'API.' + rtm.split('API.')[1].split(' ')[0].split('(')[0].replace(/[^a-zA-Z0-9\.\[\]]/g,'').replace(/\.$/,'')
              routes[inroute].methods.push(rtmc) if rtmc.length and rtmc.split('.').length > 1 and rtmc not in routes[inroute].methods
        else if method.name?
          if not method.logs? and line.indexOf('API.log') isnt -1
            log = line.split('API.log')[1]
            method.logs ?= []
            method.logs.push log
            lar = (log.split('+')[0].split('#')[0] + method.args.join('')).toLowerCase().replace(/[^a-z0-9]/g,'')
            logs[lar] = method.name
          method.lines += 1
          method.code += '\n' + line
          for tp in ['API.','HTTP.']
            li = line.indexOf(tp)
            if li isnt -1
              parts = line.split tp
              parts.shift()
              for p in parts
                p = if tp is 'API.' then tp + p.split(' ')[0].split('(')[0].split(')')[0].trim() else p.trim().replace('call ','').replace('call(','')
                if tp is 'API.' and p not in method.calls and li isnt line.indexOf('API.settings') and li isnt line.indexOf('API.add')
                  if p.indexOf('API.settings') isnt -1
                    stng = p.replace(/\?/g,'').split(')')[0].replace(/,$/,'')
                    method.settings ?= []
                    method.settings.push(stng) if stng not in method.settings
                    settings.push(stng) if stng not in settings
                  else if p.indexOf('?') is -1
                    pt = p.replace(/[^a-zA-Z0-9\.\[\]]/g,'').replace(/\.$/,'')
                    if pt.length and pt.split('.').length > 1 and pt not in method.calls
                      method.calls.push pt
                      called[pt] ?= []
                      called[pt].push method.name
                else if tp is 'HTTP.' and p not in method.remotes
                  method.remotes.push p
  
    _read = (d) ->
      stats = fs.statSync(d)
      #if stats.isSymbolicLink()
      #  console.log d
      if stats.isDirectory()
        for f in fs.readdirSync d
          _read d + '/' + f
      else if d.indexOf('structure.coffee') is -1
        _parse d
    _read src

    for rk in _.keys(routes).sort()
      for mt in routes[rk].methods
        if methods[mt]? and (not methods[mt].routes? or rk not in methods[mt].routes)
          methods[mt].routes ?= []
          methods[mt].routes.push rk
    for c in collections
      cna = c.replace('@','')
      re = new RegExp('API.' + cna, 'g')
      res = new RegExp('API.settings.' + cna, 'g')
      for m of methods
        mb = methods[m].code.replace(re,'').replace(res,'').replace(/@/g,'')
        if mb.indexOf(cna+'.') isnt -1
          methods[m].collections ?= {}
          methods[m].collections[c] ?= []
          pts = mb.split(cna+'.')
          pts.shift() if mb.indexOf(cna) isnt 0
          for pt in pts
            pt = pt.split(' ')[0].split('(')[0].split("'")[0].split('"')[0]
            if pt not in methods[m].collections[c]
              methods[m].collections[c].push pt
    for cl of called
      methods[cl].called = called[cl].sort() if methods[cl]? # where are the missing ones? in collections?
    API.structure._structured = count: _.keys(methods).length, collections: collections.sort(), settings: settings.sort(), methods: methods, helpers: helpers, routes: routes, TODO: TODO, logs: logs

  API.structure.nodeslinks(API.structure._structured)
  return API.structure._structured

API.structure.logarg2fn = (la) ->
  sr = API.structure.read()
  return sr.logs[la]
  
API.structure.method = (method) ->
  sr = API.structure.read()
  return sr.methods[method]

API.structure.methods = () ->
  return API.structure.read().methods

API.structure.collections = () ->
  return API.structure.read().collections

API.structure.nodes = () ->
  sr = API.structure.read()
  return sr.nodes ? API.structure.nodeslinks().nodes
  
API.structure.links = () ->
  sr = API.structure.read()
  return sr.links ? API.structure.nodeslinks().links

API.structure.groups = () ->
  sr = API.structure.read()
  return sr.groups ? API.structure.nodeslinks().groups

API.structure.nodeslinks = (sr,group) ->
  sr ?= API.structure.read()
  positions = {}
  counters = {}
  nds = []
  groups = []
  colls = {}
  for m of sr.methods
    if m.indexOf('API.log') is -1
      method = sr.methods[m]
      rec = {}
      rec.key = method.name
      counters[rec.key] = 1
      rec.group = method.group
      groups.push(rec.group) if rec.group not in groups
      rec.calls = method.calls
      rec.collections = method.collections
      nds.push rec
      positions[rec.key] = nds.length-1
      for c of method.collections
        colls[c] ?= []
        for pc in method.collections[c]
          apc = 'API.collection.prototype.' + pc
          colls[c].push(apc) if apc not in colls[c]

  for col of colls
    if not positions[col]?
      rec = {}
      rec.key = col
      counters[rec.key] = 1
      rec.group = 'collections'
      rec.calls = []
      for pc in colls[col]
        rec.calls.push pc
      groups.push(rec.group) if rec.group not in groups
      nds.push rec
      positions[rec.key] = nds.length-1
    else
      for pc in colls[col]
        nds[positions[col]].calls.push(pc) if pc not in nds[positions[col]].calls

  for coll in sr.collections
    if not positions[coll]? # collections that no method actually calls, but should have a node anyway
      rec = {}
      rec.key = coll
      counters[rec.key] = 1
      rec.group = 'collections'
      rec.calls = []
      groups.push(rec.group) if rec.group not in groups
      nds.push rec
      positions[rec.key] = nds.length-1

  lns = []
  extras = []
  esp = {}
  nl = nds.length
  for n of nds
    node = nds[n]
    for c in node.calls ? []
      if c.indexOf('API.log') is -1
        if not counters[c]
          counters[c] = 1
        else if not group or c.indexOf('.'+group) isnt -1
          counters[c] += 1
        pos = positions[c]
        if not pos?
          pos = esp[c]
        if not pos?
          extras.push {key: c, group: 'MISSING'}
          esp[c] = extras.length-1
          pos = nl + extras.length - 2
        if (not group or c.indexOf('.'+group) isnt -1 or node.group is group)
          lns.push {source: parseInt(n), target: pos}
    for co of node.collections ? {}
      if not counters[co]
        counters[co] = 1
      else if not group or c.indexOf('.'+group) isnt -1
        counters[co] += 1
      if not group or co.indexOf('.'+group) isnt -1 or node.group is group or group in ['collection','collections','es']
        lns.push {source: parseInt(n), target: positions[co]}

  for e of extras
    nds.push extras[e]

  for nd of nds
    cv = counters[nds[nd].key] ? 1
    nds[nd].value = cv
    nds[nd].size = cv

  API.structure._structured.nodecount ?= nds.length
  API.structure._structured.linkcount ?= lns.length
  API.structure._structured.nodes ?= nds
  API.structure._structured.links ?= lns
  API.structure._structured.groups ?= groups

  return nodes: nds, links: lns, groups: groups.sort()
