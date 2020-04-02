
import twit from 'twit'
import Future from 'fibers/future'

# https://developer.twitter.com/en/docs/tweets/post-and-engage/api-reference/post-statuses-update
# https://github.com/ttezel/twit

API.use ?= {}
API.use.twitter = {}

'''API.add 'use/twitter',
  get:
    roleRequired: 'root'
    action: () ->
      return API.use.twitter.tweet this.queryParams'''

API.add 'use/twitter/oauth', get: () -> return API.use.twitter.oauth this.queryParams



API.use.twitter.oauth = (params) ->
  return 'oauth?'

API.use.twitter.tweet = (params={},perms) ->
  perms ?= API.settings.use?.twitter?.access
  return undefined if not perms?

  params = {status: params} if typeof params is 'string'
  if typeof params.status is 'string' and params.status.length < 280
    T = new twit(perms)
    T.post 'statuses/update', { status: params.status }
    return true
  else
    return false
