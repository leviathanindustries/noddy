
import fs from 'fs'
# http://zenodo.org/dev
# https://zenodo.org/api/deposit/depositions
# api key required: http://zenodo.org/dev#restapi-auth
# requires a token be provided as query param on all requests, called ?access_token=

# token set in openaccessbutton section of settings, as this zenodo use endopint is being created for oabutton first
# API.settings.openaccessbutton.zenodo_token
# there is a CL zenodo account, and an access token could be created for it too, as a default, but no need yet so not done
# so expect anything using this endpoint to provide a token (or could use cl default one when it has been added)

# access token would require deposit:write and deposit:actions permission in order to deposit something AND then publish it

# need to POST to create a deposition
# then POST to upload files to the deposition
# then POST to publish the deposition

API.use ?= {}
API.use.zenodo = {}
API.use.zenodo.deposition = {}

# oabutton also wants to be able to search zenodo for papers (unless SHARE covers it)
# https://github.com/OAButton/backend/issues/110
# but zenodo does not have a search API yet - due in the autumn
# see https://zenodo.org/features

API.use.zenodo.deposition.create = (metadata,up,token) ->
  # necessary metadata is title and description and a creators list with at least one object containing name in format Surname, name(s)
  # useful metadata is access_right, license, doi
  # https://zenodo.org/dev#restapi-rep-meta
  token ?= API.settings.zenodo?.token
  return false if not token? or not metadata? or not metadata.title? or not metadata.description?
  url = 'https://zenodo.org/api/deposit/depositions' + '?access_token=' + token
  data = {metadata: metadata}
  if not data.metadata.upload_type
    data.metadata.upload_type = 'publication'
    data.metadata.publication_type = 'article'
  # required field, will blank list work? If not, need object with name: Surname, name(s) and optional affiliation and creator
  data.metadata.creators ?= [{name:"Open Access Button"}]
  try
    if up?
      c = HTTP.call 'POST', url, {data:data,headers:{'Content-Type':'application/json'}}
      API.use.zenodo.deposition.upload c.data.id, up.content, up.file, up.name, up.url, token
      API.use.zenodo.deposition.publish(c.data.id,token) if up.publish
      return c.data
    else
      # returns a zenodo deposition resource, which most usefully has an .id parameter (to use to then upload files to)
      return HTTP.call('POST',url,{data:data,headers:{'Content-Type':'application/json'}}).data
  catch err
    return {status: 'error', data: err, error: err}

API.use.zenodo.deposition.upload = (id,content,file,name,url,token) ->
  token ?= API.settings.zenodo?.token
  return false if not token? or not id?
  uploadurl = 'https://zenodo.org/api/deposit/depositions/' + id + '/files' + '?access_token=' + token
  try
    # returns back a deposition file, which has an id. Presumably from this we can calculate the URL of the file
    # TODO for now we are only expecting content from the file attribute, but 
    # how to get it if given content directly or url? need to pass that instead
    p = HTTP.call('POST',uploadurl,{npmRequestOptions:{body:null,formData:{file:fs.createReadStream(file),name:name}},headers:{'Content-Type':'multipart/form-data'}})
    return p.data
  catch err
    return {status: 'error', error: err}

API.use.zenodo.deposition.publish = (id,token) ->
  # NOTE published things cannot be deteted
  token ?= API.settings.zenodo?.token
  return false if not token? or not id?
  url = 'https://zenodo.org/api/deposit/depositions/' + id + '/actions/publish' + '?access_token=' + token
  try
    return HTTP.call('POST',url).data
  catch err
    return {status: 'error', error: err}

API.use.zenodo.deposition.delete = (id,token) ->
  token ?= API.settings.zenodo?.token
  return false if not token? or not id?
  url = 'https://zenodo.org/api/deposit/depositions/' + id + '?access_token=' + token
  try
    HTTP.call('DELETE',url)
    return {}
  catch err
    return {status: 'error', error: err}
