
# whenever a build script or similar runs, it can ping this endpoint to record
# a reload event. Then any sites polling for changes can reload the pages

reloads = new API.collection "reload"

API.add 'reload/:service',
  get: () ->
    return if r = reloads.get(this.urlParams.service) then r else false
  post: () ->
    if API.settings.service?[this.urlParams.service]?
      r = reloads.get this.urlParams.service
      if not r?
        reloads.insert _id: this.urlParams.service, count: 1
      else
        reloads.update this.urlParams.service, {count: r.count+1}
      return true
    else
      return false