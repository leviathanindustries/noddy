
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
  params.refresh ?= 900000 # fifteen minutes
  originals = []
  localcopy = '.medrxivlocalcopy/covid.json'
  if fs.existsSync(localcopy) and ((new Date()) - fs.statSync(localcopy).mtime) < params.refresh
    original = JSON.parse fs.readFileSync(localcopy)
  else
    res = HTTP.call 'GET', 'https://connect.medrxiv.org/relate/collection_json.php?grp=181'
    original = JSON.parse res.content
    fs.mkdirSync('.medrxivlocalcopy') if not fs.existsSync '.medrxivlocalcopy'
    fs.writeFileSync localcopy, JSON.stringify(originals)
  recs = []
  for c of original.rels
    if params.size and recs.length is params.size
      break
    else if not params.from or parseInt(c) >= params.from
      recs.push if params.format then API.use.medrxiv.format(original.rels[c]) else original.rels[c]
  return total: original.rels.length, data: recs

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
  try metadata.published = re.rel_date
  return metadata