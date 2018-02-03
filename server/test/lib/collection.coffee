

import Future from 'fibers/future'

API.add 'collection/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.collection.test(this.queryParams.verbose)

API.collection.test = (verbose) ->
  result = {passed:[],failed:[]}

  try
    tc = new API.collection {index:API.settings.es.index + '_test',type:'collection'}
    tc.delete true # get rid of anything that could be lying around from old tests
    tc.map()

  result.recs = [
    {_id:1,hello:'world',lt:1},
    {_id:2,goodbye:'world',lt:2},
    {goodbye:'world',hello:'sunshine',lt:3},
    {goodbye:'marianne',hello:'sunshine',lt:4}
  ]

  tests = [
    () ->
      console.log 0
      tc.insert(r) for r in result.recs
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.count = tc.count()
      return result.count is result.recs.length
    () ->
      console.log 1
      result.search = tc.search()
      result.stringSearch = tc.search 'goodbye:"marianne"'
      return result.stringSearch?.hits?.total is 1
    () ->
      console.log 2
      result.objectSearch = tc.search {hello:'sunshine'}
      return result.objectSearch?.hits?.total is 2
    () ->
      result.idFind = tc.find(1)
      return typeof result.idFind is 'object'
    () ->
      result.strFind = tc.find 'goodbye:"marianne"'
      return typeof result.strFind is 'object'
    () ->
      result.objFind = tc.find {goodbye:'marianne'}
      return typeof result.objFind is 'object'
    () ->
      result.objFindMulti = tc.find {goodbye:'world'}
      return typeof result.objFind is 'object'
    () ->
      result.each = tc.each 'goodbye:"world"', () -> return
      return result.each is 2
    () ->
      result.update = tc.update {hello:'world'}, {goodbye:'world'}
      return result.update is 1
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      result.retrieveUpdated = tc.find({hello:'world'});
      return result.retrieveUpdated.goodbye is 'world'
    () ->
      result.goodbyes = tc.count('goodbye:"world"');
      return result.goodbyes is 3
    () ->
      result.lessthan3 = tc.search 'lt:<3'
      return result.lessthan3.hits.total is 2
    () ->
      result.remove1 = tc.remove(1)
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      return result.remove1 is true
    () ->
      result.helloWorlds = tc.count {hello:'world'}
      return result.helloWorlds is 0
    () ->
      result.remove2 = tc.remove {hello:'sunshine'}
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      return result.remove2 is 2
    () ->
      result.remaining = tc.count()
      return result.remaining is 1
    () ->
      result.removeLast = tc.remove(2)
      return result.removeLast is true
    () ->
      future = new Future()
      setTimeout (() -> future.return()), 999
      future.wait()
      return tc.count() is 0
  ]

  # TODO add tests for searching with [ TO ]
  # also test for updating with dot.notation and updating things to false or undefined
  # and updating things within objects that do not yet exist, or updating things in lists with numbered dot notation
  # also add a test to read and maybe set the mapping, get terms, and do random search, as tests of the underlying es functions too

  (if (try tests[t]()) then (result.passed.push(t) if result.passed isnt false) else result.failed.push(t)) for t of tests
  result.passed = result.passed.length if result.passed isnt false and result.failed.length is 0
  result = {passed:result.passed} if result.failed.length is 0 and not verbose
  return result

