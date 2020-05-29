
API.use ?= {}
API.use.ricks = {}

API.add 'use/ricks', get: () -> return 'Use ricks'
API.add 'use/ricks/:which/autocomplete', get: () -> return API.use.ricks.autocomplete this.urlParams.which, this.queryParams.q

API.add 'use/ricks/funder/:id', get: () -> return API.use.ricks.get 'funder', this.urlParams.id, this.queryParams
API.add 'use/ricks/institution/:id', get: () -> return API.use.ricks.get 'institution', this.urlParams.id, this.queryParams
API.add 'use/ricks/journal/:id', get: () -> return API.use.ricks.get 'journal', this.urlParams.id, this.queryParams

API.add 'use/ricks/permissions/:doipre/:doipost', get: () -> return API.use.ricks.permissions.doi this.urlParams.doipre + '/' + this.urlParams.doipost, this.queryParams.affiliation, this.queryParams.uid
API.add 'use/ricks/permissions/:doipre/:doipost/:doimore', get: () -> return API.use.ricks.permissions.doi this.urlParams.doipre + '/' + this.urlParams.doipost + '/' + this.urlParams.doimore, this.queryParams.affiliation, this.queryParams.uid



# https://rickscafe-api.herokuapp.com/permissions/doi/
_ricks_url = 'https://api.greenoait.org'

API.use.ricks.autocomplete = (which, q) ->
  which += 's' if not which.endsWith 's'
  # which can be funders, institutions, journals, topics
  ru = _ricks_url + '/autocomplete/' + which + '/name/' + q
  API.log 'Autocomplete to Ricks for ' + ru
  try
    return HTTP.call('GET', ru).data
  catch err
    return err

API.use.ricks.permissions = {}
API.use.ricks.permissions.doi = (doi, affiliation, uid) ->
  ru = _ricks_url + '/permissions/doi/' + meta.doi
  if affiliation
    ru += '?affiliation=' + affiliation
  else if uid and uc = API.service.oab.deposit.config(uid)
    ru += '?affiliation=' + uc.ROR_ID if uc.ROR_ID
  API.log 'Permissions check connecting to Ricks for ' + ru
  try
    return HTTP.call('GET', ru).data
  catch err
    return err

API.use.ricks.get = (which, id, ids={}) ->
  which = which.replace(/s$/,'')
  delete ids[which]
  ru = _ricks_url + '/' + which + '/' + id + '?'
  ru += k + '=' + ids[k] + '&' for k of ids
  API.log 'Get from Ricks for ' + ru
  try
    return HTTP.call('GET', ru).data
  catch
    return undefined
  
API.use.ricks.funders = {}
API.use.ricks.funders.get = (id, qp) ->
  return API.use.ricks.get 'funder', id, qp

API.use.ricks.institutions = {}
API.use.ricks.institutions.get = (id, qp) ->
  return API.use.ricks.get 'institution', id, qp

API.use.ricks.journals = {}
API.use.ricks.journals.get = (issn, qp) ->
  return API.use.ricks.get 'journal', issn, qp
