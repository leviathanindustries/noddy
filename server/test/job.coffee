

import Future from 'fibers/future'

API.add 'job/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.job.test this.queryParams.verbose, not this.queryParams.cleanup?

API.job._test = {
  counter: 0,
  times: [],
  diffs: [],
  run: () ->
    API.job._test.times.push(Date.now())
    if API.job._test.times.length > 1
      API.job._test.diffs.push API.job._test.times[API.job._test.times.length-1] - API.job._test.times[API.job._test.times.length-2]
    API.job._test.counter += 1
}
API.job.test = (verbose,cleanup=true) ->
  console.log('Starting job test') if API.settings.dev

  result = {passed:[],failed:[]}

  job_limit.remove group: 'JOBTEST'
  job_job.remove group: 'JOBTEST'
  job_process.remove group: 'JOBTEST'
  job_processing.remove group: 'JOBTEST'
  job_result.remove group: 'JOBTEST'

  tests = []

  if API.settings.job?.startup is true
    tests.push () ->
      result.limitstart = Date.now()
      result.diffs = []
      result.first = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST'
      tmr = Date.now()
      result.diffs.push tmr - result.limitstart
      result.second = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST'
      tmr2 = Date.now()
      result.diffs.push tmr2 - tmr
      result.third = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST'
      result.limitend = Date.now()
      result.diffs.push result.limitend - tmr2
      result.limitdifference = result.limitend - result.limitstart
      return result.first is true and result.second is true and result.third is true and result.limitdifference > 4500
    tests.push () ->
      result.stlimitstart = Date.now()
      API.job._test.counter = 0
      API.job._test.times = []
      API.job._test.diffs = []
      Meteor.setTimeout (() -> API.job.limit 1500, 'API.job._test.run', undefined, 'JOBTEST'), 1
      Meteor.setTimeout (() -> API.job.limit 1500, 'API.job._test.run', undefined, 'JOBTEST'), 1
      Meteor.setTimeout (() -> API.job.limit 1500, 'API.job._test.run', undefined, 'JOBTEST'), 1
      while API.job._test.counter isnt 3
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 1000
        future.wait()
      result.sttimes = API.job._test.times
      result.stdiffs = API.job._test.diffs
      result.stlimitend = Date.now()
      result.stlimitdifference = result.stlimitend - result.stlimitstart
      API.job._test.counter = 0
      API.job._test.times = []
      API.job._test.diffs = []
      return result.stlimitdifference > 4500
    tests.push () ->
      result.limits = job_limit.search({group:"JOBTEST"},{sort:{createdAt:{order:'asc'}}})?.hits?.hits
      result.greater = true
      result.lmdiffs = []
      ts = true
      for lm in result.limits
        if lm._source.last?
          if ts isnt true
            diff = lm._source.last - ts
            result.lmdiffs.push diff
            result.greater = diff > 1500
          ts = lm._source.last
      return result.greater is true
    tests.push () ->
      result.rlimitstart = Date.now()
      result.rfirst = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST', 1000000
      result.rsecond = API.job.limit 1500, 'API.job.running', undefined, 'JOBTEST', 1000000
      result.rlimitend = Date.now()
      result.rlimitdifference = result.rlimitend - result.rlimitstart
      return result.rfirst is true and result.rsecond is true and result.rlimitdifference < 1500
    tests.push () ->
      result.job = API.job.create {group: 'JOBTEST', refresh: true, processes:['API.job.running','API.job.running']}
      return result.job._id?
    tests.push () ->
      while result.progress?.progress isnt 100
        future = new Future()
        Meteor.setTimeout (() -> future.return()), 1500
        future.wait()
        result.progress = API.job.progress result.job._id
        return true if result.progress.progress is 100
    tests.push () ->
      result.results = API.job.results result.job._id
      return _.isEqual result.results, [true,true]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose

  if cleanup
    job_job.remove group: 'JOBTEST'
    job_process.remove group: 'JOBTEST'
    job_processing.remove group: 'JOBTEST'
    job_result.remove group: 'JOBTEST'
    job_limit.remove group: 'JOBTEST'

  console.log('Ending job test') if API.settings.dev

  return result

