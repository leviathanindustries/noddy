
import fs from 'fs'

# for now just gets what is needed for the covidpapers work

# json dump of their relevant preprints

# https://connect.medrxiv.org/relate/collection_json.php?grp=181

API.use ?= {}
API.use.medrxiv = {}

API.add 'use/medrxiv', get: () -> return API.use.medrxiv.search this.queryParams
API.add 'use/medrxiv/covid', get: () -> return API.use.medrxiv.covid this.queryParams



API.use.medrxiv.search = (params) ->
  return 'TODO'

API.use.medrxiv.covid = (params={}) ->
  params.format ?= true
  params.format = false if params.format is 'false' or params.format is false
  params.size ?= 10
  params.from = parseInt(params.from) if typeof params.from is 'string'
  params.refresh = parseInt(params.refresh) if typeof params.refresh is 'string'
  params.refresh ?= 14400000 # four hours
  originals = {}
  localcopy = '.medrxivlocalcopy/covid.json'
  if fs.existsSync(localcopy) and ((new Date()) - fs.statSync(localcopy).mtime) < params.refresh
    originals = JSON.parse fs.readFileSync(localcopy)
  else
    res = HTTP.call 'GET', 'https://connect.medrxiv.org/relate/collection_json.php?grp=181'
    originals = JSON.parse res.content
    fs.mkdirSync('.medrxivlocalcopy') if not fs.existsSync '.medrxivlocalcopy'
    fs.writeFileSync localcopy, JSON.stringify(originals)
  recs = []
  for c of originals.rels
    if params.size and recs.length is params.size
      break
    else if not params.from or parseInt(c) >= params.from
      if not params.q or JSON.stringify(originals.rels[c]).toLowerCase().indexOf(params.q.toLowerCase()) isnt -1
        recs.push if params.format then API.use.medrxiv.format(originals.rels[c]) else originals.rels[c]
  return total: _.keys(originals.rels).length, data: recs

API.use.medrxiv.format = (rec, metadata={}) ->
  try metadata.title ?= rec.rel_title
  try metadata.doi ?= rec.rel_doi
  try metadata.url ?= rec.rel_link
  try metadata.abstract ?= rec.rel_abs
  try
    metadata.author ?= []
    for ar in rec.rel_authors
      a = {}
      a.name = ar.author_name
      a.family = a.name.split(' ').pop()
      a.given = a.name.split(' ')[0]
      a.affiliation = {name: ar.author_inst} if ar.author_inst
      metadata.author.push a
  try
    metadata.published ?= rec.rel_date
    delete metadata.published if metadata.published.split('-').length isnt 3
  return metadata
