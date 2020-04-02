
API.add 'scripts/lantern_wellcome_users',
  csv: true
  get: 
    #authRequired: 'root'
    action: () ->
      return job_job.fetch 'service:lantern AND wellcome:true', {sort: ['email','created_date'], fields: ['_id','name','count','created_date','email']}, false