
# https://www.nlm.nih.gov/mesh/meshhome.html

import fs from 'fs'

API.use ?= {}
API.use.mesh = {}

@mesh_heading = new API.collection {index:"mesh",type:"heading"}

API.add 'use/mesh', () -> return mesh_heading.search this

API.add 'use/mesh/search', get: () -> return API.use.mesh.search this.queryParams

API.add 'use/mesh/load',
  get: 
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> 
      return API.use.mesh.load()

API.add 'use/mesh/:id', get: () -> return API.use.mesh.get this.urlParams.id



API.use.mesh.get = (uid) ->
  return mesh_heading.find uid 

API.use.mesh.search = (params) ->
  return true

API.use.mesh.load = () ->
  infile = '/home/cloo/mesh2020'
  values = API.convert.xml2json fs.readFileSync infile
  res = _.keys values
  values = undefined

  API.mail.send
    to: 'alert@cottagelabs.com'
    subject: 'MESH headings load completed'
    text: JSON.stringify res

  return res
