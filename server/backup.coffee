
import moment from 'moment'

# if ES has a backup config in it, make sure it is configured
# which means a creation of a snapshot config on ES
# and creation of a job to run to create snapshots at regular intervals

#backup_register = new API.collection index: API.settings.es.index + "_backup", type: "register"

API.backup = {}

if API.settings.backup?.enabled and API.settings.backup.startup
  API.log msg: 'Starting backup process', function: 'API.backup.startup'
  opts =
    type: "s3"
    settings:
      server_side_encryption: true
      compress: true
      bucket: API.settings.backup.bucket
      region: API.settings.backup.region
  #API.es.call 'PUT', '/_snapshot/' + (API.settings.name ? 'noddy') + '_' + (API.settings.backup.name ? 'backup'), opts
  # create a job to create snapshot at 0500 every day
  
#also requires that ES has s3 backups plugin installed and the ES config contain cloud.aws.access_key and secret_key
#which must give permissions as described in:
#https://github.com/elastic/elasticsearch-cloud-aws/tree/v2.4.2#version-242-for-elasticsearch-14
#does this mean the keys will be in the index somewhere, regardless of whether I pass them in?
#if so may as well pass them in than set them in ES

#backups should only run on live. If we are on dev, do not run the backup
#Even if we did want to, running one triggered by a dev job and a non-dev job
#could result to two snapshots trying to run at the same time, which would fail
#Could have a way to allow the live backup to include dev collections, if necessary

#but will need to be able to make them run on dev for testing... and if running dev and live 
#on separate indexes, that would not matter



API.backup.register = (index,type) ->
  return false
  if index
    backup_register.insert index + (if type then '_' + type else ''), {index:index,type:type}
    return true
  else
    indexes = []
    for bup in backup_register.fetch()
      indexes.push(bup.index) if bup.index? and bup.index not in indexes
    return indexes
    
API.backup.history = (size=100) ->
  history = API.logstack()
  size = size - history.length
  if size > 0
    t = true
    #res = API.es.call 'GET', API.settings.es.index + '_log/_search?size=' + size + '&sort=createdAt:desc&q=function:*backup*'
    #history.push(h._source) for h in res.hits.hits
  return history

# https://www.elastic.co/guide/en/elasticsearch/reference/1.4/modules-snapshots.html
API.backup.snapshot = (indices=API.backup.register(), title=moment(Date.now(), "x").format("YYYYMMDD"), unavailable=true, global=false) ->
  # Perhaps starting snapshot command could check to see if there is one still supposedly running
  # then the snapshot command wait and then try to run the new snapshot once the old one is done?
  # maybe it depends if the title and indexes are the same?
  indices = indices.join(',') if typeof indices isnt 'string'
  if indices.length
    API.log msg: 'Starting backup snapshot', function: 'API.log.snapshot', notify: true
    #API.es.call 'PUT', '/_snapshot/' + (API.settings.name ? 'noddy') + '_' + (API.settings.backup.name ? 'backup') + '/' + title, {indices: indices, ignore_unavailable: unavailable, include_global_state: global}
    # this should start off some monitor that keeps checking the snapshot status to find out when it is done
    # once it is done, create a log saying it is done
    return title
  else
    return false

API.backup.restore = (title, indices=API.backup.register(), type, unavailable=true, global=false) ->
  indices = indices.join(',') if typeof indices isnt 'string'
  type = type.join(',') if typeof type isnt 'string'
  opts = 
    ignore_unavailable: unavailable
    include_global_state: global
  opts.indices = indices if indices.length
  API.log msg: 'Starting backup restore', function: 'API.backup.restore', notify: true
  if type? # if there is a type it could be more than one from one index, but should only be from one index
    opts['rename_pattern'] = "(.+)" # check that these rename patterns work for my needs
    opts['rename_replacement'] = "temp_restore_" + type.replace(/,/g,'_') + "_$1"
  else
    # if not doing a restore for a type, in which case restoring to a new index name, need to close the index we will restore to first
    # otherwise restore will not work. Running the restore reopens the index once it is complete
    for idx in indices.split(',')
      a = true
      #API.es.call 'POST', '/' + idx + '/_close' # note may need to alter ES.call to accept this as is without adding _dev?
  #API.es.call 'POST', '/_snapshot/' + (API.settings.name ? 'noddy') + '_' + (API.settings.backup.name ? 'backup') + '/' + title + '/_restore', opts
  # need to track the restore progress, and once done, update a log or something, and maybe notify?
  # and if a type name was set, need to reindex it then delete the temp one
  #if type?
  # my es module has a reindex function already, can use that then delete the temp one
  return

API.backup.remove = (title) ->
  # it is possible to remove an entire snapshot record, in which case it will not exist locally but content will still actually be there remotely
  # whereas removing a specific snapshot removes the files that created it, if those files are not also needed by some other snapshot
  # for now this only handles removing a specific snapshot
  return false if not title?
  #API.es.call 'DELETE', '/_snapshot/' + (API.settings.name ? 'noddy') + '_' + (API.settings.backup.name ? 'backup') + '/' + title
  return true
  
# a simple way to backup by dump of an index / type to disk
# could include _mapping in the dump as well?
# should this have an encrypt or anonymise function?
API.backup.disk = (index,type) ->
  return

# could also have a simple load from disk file?
# would need to know the file is on the machine running the operation, e.g. not a different cluster machine?
# or create as jobs, or use the store API?
API.backup.load = (index,type) ->
  # if file type is txt assume a standard ES import format
  # if json, see if it is a search result or a list of records
  # if a search result, see if the _mapping has been stuck into it
  return
  
API.backup.status = () ->
  # could get the last api.log of a started and completed backup timestamp?
  # could get whole history()
  # could also get register()
  return #API.es.call('GET', '/_snapshot/_status'), # check this does not leak aws keys
