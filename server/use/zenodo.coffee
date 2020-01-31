

import fs from 'fs'
import stream from 'stream'

# http://zenodo.org/dev
# https://zenodo.org/api/deposit/depositions
# api key required: http://zenodo.org/dev#restapi-auth
# requires a token be provided as query param on all requests, called ?access_token=

# token set in openaccessbutton section of settings, as this zenodo use endopint is being created for oabutton first
# there is a CL zenodo account, and an access token could be created for it too, as a default, but no need yet so not done
# so expect anything using this endpoint to provide a token (or could use cl default one when it has been added)

# access token would require deposit:write and deposit:actions permission in order to deposit something AND then publish it

# need to POST to create a deposition
# then POST to upload files to the deposition
# then POST to publish the deposition

API.use ?= {}
API.use.zenodo = {}
API.use.zenodo.deposition = {}
API.use.zenodo.records = {}

API.add 'use/zenodo',
  get: () -> return API.use.zenodo.records.search this.queryParams.q

API.add 'use/zenodo/:doipre/:doipost',
  get: () -> return API.use.zenodo.records.doi this.urlParams.doipre + '/' + this.urlParams.doipost

# oabutton also wants to be able to search zenodo for papers (unless SHARE covers it)
# https://github.com/OAButton/backend/issues/110
# but zenodo does not have a search API yet - due in the autumn
# see https://zenodo.org/features
# NOTE zenodo can now be searched, technically in test, at zenodo.org/api/records
# see search page for instructions (it is ES)
# https://help.zenodo.org/guides/search/

API.use.zenodo.records.search = (q,dev=API.settings.dev) ->
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/records?q=' + q # just do simple string queries for now
  res = HTTP.call('GET', url).data # could do a post if q is more complex...
  return res

API.use.zenodo.records.get = (q,dev=API.settings.dev) ->
  r = API.use.zenodo.records.search q, dev
  try
    # worth doing any checks on this first result?
    return r.hits.hits[0] # appears to be the complete record so no need to get from /api/records/CONCEPTRECID
  catch
    return undefined

API.use.zenodo.records.doi = (doi,dev=API.settings.dev) ->
  return API.use.zenodo.records.get 'doi:"' + doi + '"', dev

API.use.zenodo.records.title = (title,dev=API.settings.dev) ->
  return API.use.zenodo.records.get 'title:"' + title + '"', dev

API.use.zenodo.deposition.create = (metadata,up,token,dev=API.settings.dev) ->
  # necessary metadata is title and description and a creators list with at least one object containing name in format Surname, name(s)
  # useful metadata is access_right, license, doi
  # https://zenodo.org/dev#restapi-rep-meta
  token ?= if dev then API.settings.use?.zenodo?.sandbox else API.settings.use?.zenodo?.token
  return false if not token? or not metadata? or not metadata.title? or not metadata.description?
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions'
  API.log 'Using zenodo to create deposition to URL ' + url
  url += '?access_token=' + token
  data = {metadata: metadata}
  if not data.metadata.upload_type
    data.metadata.upload_type = 'publication'
    data.metadata.publication_type = 'article'
  # required field, will blank list work? If not, need object with name: Surname, name(s) and optional affiliation and creator
  data.metadata.creators ?= [{name:"Button, Open Access"}]
  try
    if up?
      rs = HTTP.call('POST', url, {data:data,headers:{'Content-Type':'application/json'}}).data
      rs.uploaded = API.use.zenodo.deposition.upload(rs.id, up.content, up.file, up.name, up.url, token) if rs?.id? and (up.content or up.file)
      rs.published = API.use.zenodo.deposition.publish(rs.id,token) if up.publish
      return rs
    else
      # returns a zenodo deposition resource, which most usefully has an .id parameter (to use to then upload files to)
      return HTTP.call('POST',url,{data:data,headers:{'Content-Type':'application/json'}}).data
  catch err
    return {status: 'error', data: err, error: err}

API.use.zenodo.deposition.upload = (id,content,file,name,url,token,dev=API.settings.dev) ->
  token ?= if dev then API.settings.use?.zenodo?.sandbox else API.settings.use?.zenodo?.token
  return false if not token? or not id?
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '/files' + '?access_token=' + token
  try
    return JSON.parse API.http.post(url, (content ? file), {name: name}).body
  catch err
    return {status: 'error', error: err}

API.use.zenodo.deposition.publish = (id,token,dev=API.settings.dev) ->
  # NOTE published things cannot be deteted
  token ?= if dev then API.settings.use?.zenodo?.sandbox else API.settings.use?.zenodo?.token
  return false if not token? or not id?
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '/actions/publish' + '?access_token=' + token
  try
    return HTTP.call('POST',url).data
  catch err
    return {status: 'error', error: err}

API.use.zenodo.deposition.delete = (id,token,dev=API.settings.dev) ->
  token ?= if dev then API.settings.use?.zenodo?.sandbox else API.settings.use?.zenodo?.token
  return false if not token? or not id?
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '?access_token=' + token
  try
    HTTP.call 'DELETE', url
    return true
  catch err
    return {status: 'error', error: err}
