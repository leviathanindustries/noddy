

API.add 'mail/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.mail.test(this.queryParams.verbose)

API.mail.test = (verbose) ->
  result = {passed:[],failed:[]}

  tests = [
    () ->
      result.send = API.mail.send
        from: API.settings.mail.from
        to: API.settings.mail.to
        subject: 'Test me via default POST'
        text: "hello"
        html: '<p><b>hello</b></p>'
      return result.send?.statusCode is 200
    () ->
      result.validate = API.mail.validate API.settings.mail.to
      return result.validate?.is_valid is true
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result