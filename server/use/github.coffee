
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
  return total:issues.length, data:issues



API.use.github.issue = (opts={}) ->
  opts.username ?= API.settings.use?.github?.users?.default?.username ? '' # must be a user with access to the repo
  opts.password ?= API.settings.use?.github?.users?[opts.username].password ? API.settings.use?.github?.users?.default?.password ? ''
  opts.org ?= opts.owner ? ''
  opts.repo ?= ''
  
  if opts.username and opts.password and opts.org and opts.repo and opts.title
    url = 'https://' + opts.username + ':' + opts.password + '@api.github.com/repos/' + opts.org + '/' + opts.repo + '/issues'
    issue = 
      title: opts.title
      body: opts.body
      assignee: opts.assignee ? opts.assign
      milestone: opts.milestone
      labels: opts.labels # can this be list, comma-separated string, etc?
    res = HTTP.call 'POST', url, issue # what format if any is needed for POST to the API?
    console.log res
    return true # what is useful to return
  else
    return false

