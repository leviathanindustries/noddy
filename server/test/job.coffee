

import Future from 'fibers/future'

API.add 'job/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.job.test this.queryParams.verbose

API.job.test = (verbose) ->
  result = {passed:[],failed:[]}

  job_job.remove group: 'JOBTEST'
  job_process.remove group: 'JOBTEST'
  job_processing.remove group: 'JOBTEST'
  job_result.remove group: 'JOBTEST'

  tests = [
    () ->
      result.limitstart = Date.now()
      result.first = API.job.limit 2000, 'API.job.running', undefined, 'JOBTEST'
      result.second = API.job.limit 3000, 'API.job.running', undefined, 'JOBTEST'
      result.third = API.job.limit 1000, 'API.job.running', undefined, 'JOBTEST'
      result.limitend = Date.now()
      result.limitdifference = result.limitend - result.limitstart
      return result.first? and result.second? and result.third? and result.limitdifference > 6000 and result.first is (API.settings.job?.startup ? false) and result.first is result.second and result.second is result.third
  ]

  if API.settings.job?.startup is true
    tests.push () ->
      result.job = API.job.create {group: 'JOBTEST', refresh: true, processes:['API.job.running','API.job.running']}
      return result.job._id?
    tests.push () ->
      while result.progress?.progress isnt 100
        future = new Future()
        setTimeout (() -> future.return()), 1500
        future.wait()
        result.progress = API.job.progress result.job._id
        return true if result.progress.progress is 100
    tests.push () ->
      result.results = API.job.results result.job._id
      return _.isEqual result.results, [true,true]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  job_job.remove group: 'JOBTEST'
  job_process.remove group: 'JOBTEST'
  job_processing.remove group: 'JOBTEST'
  job_result.remove group: 'JOBTEST'

  return result

