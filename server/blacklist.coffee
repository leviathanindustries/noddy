
API.add 'blacklist',
  desc: 'Returns the values that would cause a request to the API to be refused.'
  get: () ->
    return API.blacklist()

API.add 'blacklist/reload',
  desc: 'Reloads the blacklist. This happens by default whenever a new request arrives more than an hour after the blacklist was last reloaded. It is loaded from a google doc, the ID of which must be defined in API.settings.blacklist.sheet'
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () ->
      return API.blacklist undefined, 1



API.blacklist = (request,stale=3600000) ->
  # TODO could add blacklisting by stored values in an index, instead of or in addition to from a google sheet
  try
    if API.settings.blacklist?.disabled
      return false
    else if API.settings.blacklist?.sheet
      blacklist = API.use.google.sheets.feed API.settings.blacklist.sheet, stale
      if request?
        for b in blacklist
          bad = false
          routematch = not b.route or (b.route and b.route isnt '*' and request.url.toLowerCase().indexOf(b.route.toLowerCase()) isnt -1)
          if b.key and b.key not in ['headers','params','body'] and b.value and routematch
            blc = b.key.toLowerCase()
            vlc = b.value.toLowerCase()
            for h of request.headers
              if not bad and (b is '*' or h.toLowerCase() is blc) and JSON.stringify(request.headers[h]).toLowerCase().indexOf(vlc) isnt -1
                bad = true
            if bad is false
              for p of request.query
                if not bad and (p is '*' or p.toLowerCase() is blc) and JSON.stringify(request.query[p]).toLowerCase().indexOf(vlc) isnt -1
                  bad = true
            if bad is false
              for d of request.body
                if not bad and (d is '*' or d.toLowerCase() is blc) and JSON.stringify(request.body[d]).toLowerCase().indexOf(vlc) isnt -1
                  bad = true
          else if b.key and b.key in ['headers','params','body'] and b.value and routematch and JSON.stringify(request[(if b.key is 'params' then 'query' else b.key)]).toLowerCase().indexOf(b.value.toLowerCase()) isnt -1
            bad = true
          else if b.value and routematch
            bad = (JSON.stringify(request.headers) + JSON.stringify(request.query) + JSON.stringify(request.body)).toLowerCase().indexOf(b.value.toLowerCase()) isnt -1
          else if b.route and routematch
            bad = true
          if bad
            if API.settings.log?.level is 'all'
              # don't write proper logs by default cos if blacklisting due to bombardment, logs would put load on the system
              console.log 'Blacklisting'
              console.log request.headers
              console.log request.query
              #console.log request.body
              console.log request.url
              console.log b
            try
              if b.log is true or b.log.toLowerCase() is "true"
                API.log {msg: 'blacklisted', blacklisted:{headers:request.headers, query:request.query, body:request.body, url:request.url}}
            try
              parsed = parseInt b.code
              b.code = parsed if not isNaN parsed
              b.code = undefined if b.code is ""
            return
              statusCode: b.code ? 403
              body: {status:'error', error:'blacklisted', info: b.msg ? (b.value ? 'This request') + ' is blacklisted.', contact: b.contact ? API.settings.blacklist.contact}
        return false
      else
        return blacklist
    else
      return false
  catch
    return false

