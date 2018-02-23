

API.service ?= {}
API.service.lantern = {}

API.add 'service/lantern',
  get:
    authOptional: true
    action: () ->
      if this.queryParams.doi or this.queryParams.pmid or this.queryParams.pmc
        j = {new:true,service:'lantern'}
        if this.userId
          j.user = this.userId
          j.email = this.user.emails[0].address
        j._id = job_job.insert j
        j.processes = []
        j.processes.push({doi:this.queryParams.doi}) if this.queryParams.doi
        j.processes.push({pmid:this.queryParams.pmid}) if this.queryParams.pmid
        j.processes.push({pmcid:this.queryParams.pmcid}) if this.queryParams.pmcid
        try j.refresh = parseInt(this.queryParams.refresh) if this.queryParams.refresh?
        j.wellcome = this.queryParams.wellcome
        Meteor.setTimeout (() -> API.service.lantern.job(j)), 5
        return j
      else
        return {data: 'The lantern API'}
  post:
    authOptional: true
    action: () ->
      j = {new:true,service:'lantern'}
      if this.userId
        j.user = this.userId
        j.email = this.user.emails[0].address
      try j.refresh = parseInt(this.queryParams.refresh) if this.queryParams.refresh?
      if this.request.body.email
        j.wellcome = true
        j.email = this.request.body.email
        j.refresh = 1 if not j.refresh?
      processes = if this.request.body.list then this.request.body.list else this.request.body
      if not this.userId and processes.length > 1
        return 401
      else
        j._id = job_job.insert j # quick create to respond to user
        j.processes = processes
        j.name ?= this.request.body.name
        Meteor.setTimeout (() -> API.service.lantern.job(j)), 5
        return j

API.add 'service/lantern/process',
  get:
    roleRequired: 'lantern.admin'
    action: () ->
      return if this.userId then API.service.lantern.process({doi:this.queryParams.doi,pmid:this.queryParams.pmid,pmcid:this.queryParams.pmcid}) else 401

API.add 'service/lantern/:job',
  get:
    roleRequired: 'lantern.user'
    action: () ->
      job = job_job.get this.urlParams.job
      return 401 if not API.job.allowed job, this.user
      if job
        p = API.job.progress this.urlParams.job
        job.progress = p ? 0
        return job
      else
        return 404

API.add 'service/lantern/:job/rerun',
  get:
    roleRequired: 'lantern.admin'
    action: () -> return API.job.rerun(this.urlParams.job)

API.add 'service/lantern/:job/progress',
  get: () -> 
    job = job_job.get this.urlParams.job
    if job
      pr = API.job.progress this.urlParams.job
      pr.report = job.report
      return pr
    else
      return 404

API.add 'service/lantern/:job/rename/:name',
  get:
    roleRequired: 'lantern.user'
    action: () ->
      if job = job_job.get this.urlParams.job
        if this.user.emails[0].address is job.email or API.accounts.auth 'lantern.admin', this.user
          job_job.update job._id, {report:this.urlParams.name}
          return {status: 'success'}
        else
          return 401
      else
        return 404

API.add 'service/lantern/:job/results',
  get:
    authOptional: true
    action: () ->
      job = job_job.get this.urlParams.job
      return 404 if not job
      if this.queryParams.format is 'csv'
        ignorefields = []
        if this.user?.service?.lantern?.profile?.fields
          for f of acc.service.lantern.profile.fields
            ignorefields.push(f) if acc.service.lantern.profile.fields[f] is false and ( not this.queryParams[f]? or this.queryParams[f] is 'false')
        csv = API.service.lantern.csv this.urlParams.job, ignorefields
        name = if job.name then job.name.split('.')[0].replace(/ /g,'_') + '_results' else 'results'
        this.response.writeHead 200,
          'Content-disposition': "attachment; filename="+name+".csv"
          'Content-type': 'text/csv; charset=UTF-8'
          'Content-Encoding': 'UTF-8'
        this.response.end csv
        this.done()
      else
        return API.job.results this.urlParams.job

API.add 'service/lantern/:job/original',
  get:
    roleRequired: 'lantern.user'
    action: () ->
      job = job_job.get this.urlParams.job
      return 401 if not API.job.allowed job, this.user
      fl = []
      for jb in job.processes
        delete jb.process
        # TODO actually now needs to read the input args, not the process
        fl.push jb
      ret = API.convert.json2csv undefined, undefined, fl
      name = if job.name then job.name.split('.')[0].replace(/ /g,'_') else 'original'
      this.response.writeHead 200,
        'Content-disposition': "attachment; filename="+name+"_original.csv"
        'Content-type': 'text/csv; charset=UTF-8'
        'Content-Encoding': 'UTF-8'
      this.response.end ret
      this.done()

API.add 'service/lantern/jobs',
  get:
    roleRequired: 'lantern.admin'
    action: () ->
      results = []
      job_job.each 'service:lantern', true, (job) ->
        job.processes = job.processes?.length ? 0
        results.push(job) if job.processes isnt 0
      return {total:results.length, jobs: results}

API.add 'service/lantern/jobs/:email',
  get:
    roleRequired: 'lantern.user'
    action: () ->
      results = []
      return 401 if not (API.accounts.auth('lantern.admin',this.user) or this.user.emails[0].address is this.urlParams.email)
      job_job.each 'service:lantern AND email:' + this.urlParams.email, true, (job) ->
        job.processes = job.processes.length
        results.push job
      return {total:results.length, jobs: results}

API.add 'service/lantern/processes', get: () -> return count: job_process.count 'service:lantern'
API.add 'service/lantern/processing', get: () -> return count: job_processing.count 'service:lantern'
API.add 'service/lantern/processing/reload',
  get:
    roleRequired: 'lantern.admin'
    action: () -> return API.job.reload()

API.add 'service/lantern/status',
  get: () -> return API.service.lantern.status()

API.add 'service/lantern/fields/:email',
  post:
    roleRequired: 'lantern.user'
    action: () ->
      if API.accounts.auth('lantern.admin',this.user) or this.user.emails[0].address is this.urlParams.email
        if not this.user.service.lantern.profile?
          this.user.service.lantern.profile = {fields:{}}
          API.accounts.update this.userId, {'service.lantern.profile':{fields:{}}}, this.user
        else if not this.user.service.lantern.profile.fields?
          this.user.service.lantern.profile.fields = {}
          API.accounts.update this.userId, {'service.lantern.profile.fields':{}}, this.user
        this.user.service.lantern.profile.fields[p] = this.request.body[p] for p in this.request.body
        API.accounts.update this.userId, {'service.lantern.profile.fields':this.user.service.lantern.profile.fields}, this.user
        return this.user.service.lantern.profile.fields
      else
        return 401
