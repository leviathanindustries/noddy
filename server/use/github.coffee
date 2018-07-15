
# https://developer.github.com/v3/

API.use ?= {}
API.use.github = {}

API.add 'use/github/issues', get: () -> return API.use.github.issues this.queryParams



API.use.github.issues = (opts) ->
  # https://developer.github.com/v3/issues/#list-issues-for-a-repository
  root = 'https://api.github.com/' # add username:password@ to get higher rate limit - only get 60 without auth
  page = 1
  # add param "state" with value "open" "closed" or "all" - defaults to "open"
  url = root + 'repos/' + opts.owner + '/' + opts.repo + '/issues?per_page=100&page='
  issues = []
  try
    readlast = false
    last = 1
    while page <= last
      tu = url + page
      res = HTTP.call 'GET', tu, {headers:{'User-Agent':opts.owner}}
      issues.push(d) for d in res.data
      page += 1
      try
        if not readlast
          readlast = true
          last = parseInt res.headers.link.split('next')[1].split('&page=')[1].split('>')[0]
  catch err
    return {status:'error',data:err}
  return {status:'success',total:issues.length,data:issues}

