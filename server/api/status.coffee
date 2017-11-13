
API.add 'status', get: () -> return API.status()

# TODO this could become a loop like the test system and the routes listing on the main API url
API.status = () ->
  ret =
    up:
      live:false
      local:false
      cluster:false
      dev:false
    accounts:
      total: Users.count()
      #online: API.accounts.onlinecount()
    job: false
    index: false
    lantern: false
    openaccessbutton: false

  try HTTP.call('HEAD','https://api.cottagelabs.com')
  try HTTP.call('HEAD','https://lapi.cottagelabs.com')
  try HTTP.call('HEAD','https://dev.api.cottagelabs.com')
  try
    HTTP.call('HEAD','https://capi.cottagelabs.com')
    if API.settings.cluster?.machines
      cm = 0
      for m in API.settings.cluster.machines
        try
          HTTP.call('HEAD','http://' + API.settings.cluster.machines[m] + '/api')
          cm += 1
      ret.up.cluster = cm if cm isnt 0
  # TODO if cluster is up could read the mup file then try getting each cluster machine too, and counting them
  try ret.job = API.job.status()
  try ret.index = API.es.status()
  try ret.lantern = API.service.lantern.status()
  try ret.openaccessbutton = API.service.oab.status()
  return ret




