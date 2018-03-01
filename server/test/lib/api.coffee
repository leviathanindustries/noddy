
import moment from 'moment'

test_results = new API.collection 'tests'

API.add 'test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.test this.queryParams.verbose, this.queryParams.ignore, this.queryParams.run

API.add 'test/last',
  get: () ->
    #try
    res = API.es.call 'GET', '/' + API.settings.es.index + '_log/' + moment(Date.now(), "x").format("YYYYMMDD") + '/_search?sort=createdAt:desc&q=function:"API.test"'
    if not res?
      API.es.call 'GET', '/' + API.settings.es.index + '_log/' + moment(Date.now() - 86400000 , "x").format("YYYYMMDD") + '/_search?sort=createdAt:desc&q=function:"API.test"'
    return JSON.parse res.hits.hits[0]._source.tests
    #catch
    #  return {}

API.test = (verbose,ignore=['settings','es','log'],run=[]) ->
  ignore = ignore.split(',') if typeof ignore is 'string'
  run = run.split(',') if typeof run is 'string'
  ignore.push('settings') if ignore.indexOf('settings') is -1
  ignore.push('es') if ignore.indexOf('es') is -1
  ignore.push('log') if ignore.indexOf('log') is -1

  console.log('STARTING TESTS AT ' + moment(Date.now(), "x").format("YYYYMMDD HHmm")) if API.settings.dev
  console.log('IGNORING ' + JSON.stringify(ignore)) if API.settings.dev
  console.log('RUNNING ' + JSON.stringify(run)) if run.length and API.settings.dev

  #d = new Date() # uncomment this to remove old test results, if that becomes useful
  #test_results.remove 'createdAt:<' + d.setDate(d.getDate() - 30)
  tests = passed: true
  test = (obj=API,tsts=tests) ->
    for k of obj
      if k.indexOf('_') isnt 0 and (k is 'test' or k in run or (run.length is 0 and k not in ignore)) # don't copy the settings onto the response
        if typeof obj[k] is 'function' and not obj._routes? # don't run if at the top level where _routes is defined, or would recursively call this test function
          tsts[k] = obj[k](verbose)
          tests.passed = tests.passed and (not tsts[k].failed? or tsts[k].failed.length is 0) and tsts[k].passed isnt false
          tests.notes = _.union((tests.notes ? []), tsts[k].notes) if tsts[k].notes?.length > 0
          tsts[k] = (if typeof tsts[k].passed is 'boolean' then tsts[k].passed else (if typeof tsts[k].passed is 'number' then tsts[k].passed else tsts[k].passed.length)) if (not tsts[k].failed? or tsts[k].failed.length is 0) and not verbose
        else if k isnt 'test' and typeof obj[k] is 'object' or k is 'collection'
          tsts[k] = {}
          test obj[k], tsts[k]
  test()

  try test_results.insert tests
  API.log msg: 'Completed testing', tests: tests, function:'API.test', notify: {msg:JSON.stringify(tests,undefined,2)}

  console.log('FINISHING TESTS AT ' + moment(Date.now(), "x").format("YYYYMMDD HHmm")) if API.settings.dev

  return tests
