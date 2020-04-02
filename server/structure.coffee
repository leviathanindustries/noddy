
import fs from 'fs'

noddy_structure = new API.collection "structure"

API.add 'structure', get: () -> return API.structure.read()
#API.add 'structure', () -> return noddy_structure.search this


API.structure = {}

API.structure.read = (src='/home/cloo/dev/noddy/server') ->
  #if src.indexOf('http') is 0
    # get the code from the github address to a local temp folder
    # set the src to be the root of the git folder

  #noddy_structure.remove '*'
  collections = []
  methods = {}

  # add in a parse to see if calls are made from within loops, and if so, capture their conditionals if possible
  # serve a query endpoint for the records and a holder page with the vis

  _parse = (fn) ->
    fl = fs.readFileSync(fn).toString()
    method = {}
    for line in fl.replace(/\r\n/g,'\n').split '\n'
      if line.indexOf('new API.collection') isnt -1
        coll = line.split('new ')[0].split('=')[0].trim().split(' ')[0]
        collections.push(coll) if coll not in collections
      else if line.indexOf('API.') is 0 and line.indexOf('(') isnt -1 and line.indexOf('.test') is -1 and line.indexOf('API.code') is -1 and line.indexOf('API.add') is -1 and line.indexOf('API.settings') isnt 0
        if JSON.stringify(method) isnt '{}'
          # noddy_structure.insert method
          methods[method.name] = method
        method = {}
        #method.body = line
        method.name = line.split(' ')[0]
        method.args = line.split('(')[1].split(')')[0].split(',')
        for a of method.args
          method.args[a] = method.args[a].split('=')[0].trim()
        method.calls = []
        method.remotes = []
      else if method.name?
        #method.body += '\n' + line
        for tp in ['API.','HTTP.']
          li = line.indexOf(tp)
          if li isnt -1
            parts = line.split tp
            parts.shift()
            for p in parts
              p = if tp is 'API.' then tp + p.split(' ')[0].split('(')[0].trim() else p.trim()
              if tp is 'API.' and p not in method.calls and li isnt line.indexOf('API.settings') and li isnt line.indexOf('API.add')
                method.calls.push p
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
  
  return count: _.keys(methods).length, collections: collections.sort(), methods: methods