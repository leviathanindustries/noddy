

test_results = new API.collection 'tests'

API.add 'test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.test this.queryParams.verbose

API.test = (verbose) ->
  #d = new Date() # uncomment this to remove old test results, if that becomes useful
  #test_results.remove 'createdAt:<' + d.setDate(d.getDate() - 30)
  tests = passed: true
  test = (obj=API,tsts=tests) ->
    for k of obj
      if k.indexOf('_') isnt 0 and k not in ['settings','es','log'] # don't copy the settings onto the response
        if k is 'test' and typeof obj[k] is 'function' and not obj._routes? # don't run if at the top level where _routes is defined, or would recursively call this test function
          tsts[k] = obj[k](verbose)
          tests.passed = tests.passed and (not tsts[k].failed? or tsts[k].failed.length is 0) and tsts[k].passed isnt false
          tests.notes = _.union((tests.notes ? []), tsts[k].notes) if tsts[k].notes?.length > 0
          tsts[k] = (if typeof tsts[k].passed is 'boolean' then tsts[k].passed else (if typeof tsts[k].passed is 'number' then tsts[k].passed else tsts[k].passed.length)) if (not tsts[k].failed? or tsts[k].failed.length is 0) and not verbose
        else if typeof obj[k] is 'object' or k is 'collection'
          tsts[k] = {}
          test obj[k], tsts[k]
  test()

  try test_results.insert tests
  API.log msg: 'Completed testing', tests: tests, notify: {msg:JSON.stringify(tests,undefined,2)}
  return tests
