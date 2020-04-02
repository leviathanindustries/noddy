
API.use ?= {}
API.use.instagram = {}

API.add 'use/instagram', get: () -> return API.use.instagram.list this.queryParams
API.add 'use/instagram/:account', get: () -> return API.use.instagram.list this.urlParams.account


# https://www.instagram.com/developer/embedding/

API.use.instagram.list = (account) ->
  pg = API.http.puppeteer 'https://www.instagram.com/' + account
  ls = []
  parts = pg.split('/p/')
  parts.shift()
  for p in parts
    tidy = 'https://instagram.com/p/' + p.split('/')[0] + '/media/?size=t' # size are t, m, l, default is m (t is thumbnail)
    ls.push(tidy) if tidy not in ls
  return ls

