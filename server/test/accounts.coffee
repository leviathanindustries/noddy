

import Future from 'fibers/future'

API.add 'accounts/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.accounts.test(this.queryParams.verbose)

API.accounts.test = (verbose) ->
  result = {passed:[],failed:[]}

  temail = 'a_test_account@noddy.com'
  try
    if old = API.accounts.retrieve temail # clean up old test items
      API.accounts.remove old._id
    Tokens.remove {service: 'TEST'}
    Tokens.remove {email: temail}

  tests = [
    () ->
      result.hash = API.accounts.hash 1234567
      return result.hash is API.accounts.hash 1234567
    () ->
      result.create = API.accounts.create temail
      return typeof result.create is 'object' and result.create?._id?
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.retrieved = API.accounts.retrieve temail
      return result.retrieved._id is result.create._id
    () ->
      result.addrole = API.accounts.addrole result.retrieved._id, 'testgroup.testrole'
      result.addedrole = API.accounts.retrieve result.retrieved._id
      return result.addedrole?.roles?.testgroup?.indexOf('testrole') isnt -1
    () ->
      result.authorised = API.accounts.auth 'testgroup.testrole', result.addedrole
      return result.authorised
    () ->
      result.removerole = API.accounts.removerole result.retrieved._id, 'testgroup.testrole'
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.deauthorised = API.accounts.retrieve result.retrieved._id
      return result.deauthorised.roles.testgroup.length is 0
    () ->
      result.token = API.accounts.token {email:temail,service:'TEST',action:'login'}, false
      return result.token?.email is temail and result.token?.service is 'TEST' and result.token?.token and result.token?.hash
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.logincode = Tokens.find temail
      return result.logincode?.token? and result.logincode.token is API.accounts.hash(result.token.token)
    () ->
      result.login = API.accounts.login {email:temail, token:result.token.token}
      return result.login?.account?.email is temail
    () ->
      result.logincodeRemoved = Tokens.get result.token._id
      return result.logincodeRemoved is undefined
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.loggedinResume = Tokens.find {uid:result.retrieved._id}
      return result.loggedinResume? and result.loggedinResume.resume is API.accounts.hash(result.login?.settings?.resume)
    () ->
      result.logout = API.accounts.logout result.retrieved._id
      return result.logout is true
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.noTokensAfterLogout = Tokens.find {uid:result.retrieved._id}
      return not result.noTokensAfterLogout?
  ]

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  
  try
    if acc = API.accounts.retrieve temail # clean up old test items
      API.accounts.remove acc._id
    Tokens.remove {service: 'TEST'}
    Tokens.remove {email: temail}

  return result
