
API.add 'phantom/test',
  get:
    roleRequired: (if API.settings.dev then undefined else 'root')
    action: () -> return API.phantom.test this.queryParams.verbose, this.queryParams.url, this.queryParams.find

API.phantom.test = (verbose,url='https://cottagelabs.com',find='cottage labs') ->
  result = {passed:[],failed:[]}

  tests = [
    () ->
      return API.phantom.get(url).toLowerCase().indexOf(find) isnt -1
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result
