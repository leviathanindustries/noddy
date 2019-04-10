

import marked from 'marked'

API.mail = {}

@mail_template = new API.collection "mailtemplate"
@mail_progress = new API.collection "mailprogress"

API.add 'mail/validate', get: () -> return API.mail.validate this.queryParams.email

API.add 'mail/send',
  post:
    roleRequired:'root' # how to decide roles that can post mail remotely?
    action: () ->
      #API.mail.send()
      return {}

API.add 'mail/feedback/:token',
  get: () ->
    try
      from = this.queryParams.from ? API.settings.mail?.feedback?[this.urlParams.token]?.from ? "sysadmin@cottagelabs.com"
      to = API.settings.mail?.feedback?[this.urlParams.token]?.to
      service = API.settings.mail?.feedback?[this.urlParams.token]?.service
      subject = API.settings.mail?.feedback?[this.urlParams.token]?.subject ? "Feedback"
    if to?
      API.mail.send
        service: service
        from: from
        to: to
        subject: subject
        text: this.queryParams.content
    return {}

API.add 'mail/progress',
  get:
    roleRequired: 'root'
    action: () -> return mail_progress.search this.queryParams
  post: () ->
    API.mail.progress this.request.body, this.queryParams.token
    return {}

API.add 'mail/progress/:mid',
  get: () ->
    try
      if '@' in this.urlParams.mid
        rm = mail_progress.find {'recipient.exact':this.urlParams.mid}, true
        if rm.createdAt < Date.now() - 60000 # progress checks via email are not exact, so limit to events in the last minute
          return ''
      else
        rm = mail_progress.find {'Message-Id.exact':this.urlParams.mid}, true
      return rm.event
    catch
      return ''


API.mail.send = (opts,mail_url) ->
  if API.settings.mail?.disabled
    API.log 'Sending mail is disabled, but would send', opts: opts, mail_url: mail_url
    return {}
  # also takes cc, bcc, replyTo, but not required. Can be strings or lists of strings

  if opts.template
    parts = API.mail.construct opts.template, opts.vars
    opts[p] = parts[p] for p of parts
    delete opts.template

  if not opts.text and not opts.html
    opts.text = opts.content ? opts.body ? ""
  delete opts.content

  if opts.append
    if typeof opts.append is 'string'
      if opts.html
        opts.html += opts.append
      else
        opts.text += opts.append
    else
      opts.html += opts.append.html if opts.append.html? and opts.html?
      opts.text += opts.append.text if opts.append.text? and opts.text?
    delete opts.append

  if opts.html and opts.html.indexOf('<body') is -1 # these are needed to make well-formed html emails for action buttons to work in gmail
    opts.html = '<body>' + opts.html + '</body>'
  if opts.html and opts.html.indexOf('<html') is -1
    opts.html = '<html>' + opts.html + '</html>'

  # can also take opts.headers
  # also takes opts.attachments, but not required. Should be a list of objects as per
  # https://github.com/nodemailer/mailcomposer/blob/7c0422b2de2dc61a60ba27cfa3353472f662aeb5/README.md#add-attachments

  ms = if opts.service? and API.settings.service?[opts.service]?.mail? then API.settings.service[opts.service].mail else API.settings.mail
  delete opts.service
  opts.from ?= ms.from
  opts.to ?= ms.to

  if opts.smtp or opts.attachments? or not ms.domain?
    delete opts.smtp
    mail_url ?= ms.url
    process.env.MAIL_URL = mail_url ? API.settings.mail.url
    API.log({msg:'Sending mail via mailgun SMTP',mail:opts})
    Email.send(opts)
    process.env.MAIL_URL = API.settings.mail.url if mail_url?
    return {}
  else
    url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages'
    opts.to = opts.to.join(',') if typeof opts.to is 'object'
    API.log({msg:'Sending mail via mailgun API',mail:opts,url:url})
    try
      posted = HTTP.call 'POST', url, {params:opts,auth:'api:'+ms.apikey}
      API.log {posted:posted}
      return posted
    catch err
      API.log {msg:'Sending mail failed',error:err.toString()}
      return err


API.mail.validate = (email, apikey=API.settings.mail.pubkey, cached=true) ->
  u = 'https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(email) + '&api_key=' + apikey
  try
    if cached
      checked = API.http.cache email, 'mail_validate'
      if checked
        checked.cached = true
        return checked
    res = HTTP.call('GET',u).data
    API.http.cache(email, 'mail_validate', res) if res and cached
    return res
  catch err
    API.log {msg:'Mailgun validate error',error:JSON.stringify(err),notify:{subject:'Mailgun validate error'}}
    return {}

# mailgun progress webhook target
# https://documentation.mailgun.com/user_manual.html#tracking-deliveries
# https://documentation.mailgun.com/user_manual.html#tracking-failures
API.mail.progress = (content,token) ->
  content['Message-Id'] = '<' + content['message-id'] + '>' if content['message-id']? and not content['Message-Id']?
  mail_progress.insert content
  try
    if content.event is 'dropped'
      obj = {msg:'Mail service dropped email',error:JSON.stringify(content,undefined,2),notify:{msg:JSON.stringify(content,undefined,2),subject:'Mail service dropped email'}}
      if content.domain isnt API.settings.mail.domain
        for s in API.settings.service
          if s.mail and s.mail.domain is content.domain
            obj.msg = s.servie + ' ' + obj.msg
            obj.notify.subject = obj.msg
            obj.notify.service = s.service
            obj.notify.notify = 'dropped'
      else if content.domain.indexOf('openaccessbutton') isnt -1 # TODO this should not directly refer to a service - config should be passed in
        API.mail.send {
          from: "requests@openaccessbutton.org",
          to: ["natalianorori@gmail.com"],
          subject: "mailgun dropped email",
          text: JSON.stringify(content,undefined,2)
        }, API.settings.openaccessbutton.mail_url
      API.log obj

API.mail.template = (search,template) ->
  if template
    mail_template.insert template
  else if search
    if typeof search is 'string'
      return mail_template.get(search) ? mail_template.find([{template:search},{filename:search}])
    else
      tmpls = mail_template.search search, 1000
      tpts = []
      tpts.push tp._source for tp in tmpls.hits?.hits
      return if tpts.length is 1 then tpts[0] else tpts
  else
    tmpls = mail_template.search '*', 1000
    tpts = []
    tpts.push tp._source for tp in tmpls.hits?.hits
    return tpts

API.mail.substitute = (content,vars,markdown) ->
  ret = {}
  for v of vars
    if content.toLowerCase().indexOf('{{'+v+'}}') isnt -1
      rg = new RegExp('{{'+v+'}}','gi')
      content = content.replace rg, vars[v]
  if content.indexOf('{{') isnt -1
    vs = ['subject','from','to','cc','bcc']
    for k in vs
      key = if content.toLowerCase().indexOf('{{'+k) isnt -1 then k else undefined
      if key
        keyu = if content.indexOf('{{'+key.toUpperCase()) isnt -1 then key.toUpperCase() else key
        val = content.split('{{'+keyu)[1].split('}}')[0].trim()
        ret[key] = val if val
        kg = new RegExp('{{'+keyu+'.*?}}','gi')
        content = content.replace(kg,'')
  ret.content = content
  if markdown
    ret.html = marked(ret.content)
    ret.text = ret.content.replace(/\[.*?\]\((.*?)\)/gi,"$1")
  return ret

API.mail.construct = (tmpl,vars) ->
  # if filename is .txt or .html look for the alternative too.
  # if .md try to generate a text and html option out of it
  template = API.mail.template tmpl
  md = template.filename.endsWith '.md'
  ret = if vars then API.mail.substitute(template.content,vars,md) else {content: template.content}
  if not md
    alt = false
    if template.filename.endsWith '.txt'
      ret.text = ret.content
      alt = 'html'
    else if template.filename.endsWith '.html'
      ret.html = ret.content
      alt = 'txt'
    if alt
      try
        match = {filename: template.filename.split('.')[0] + '.' + alt}
        match.service ?= template.service
        other = API.mail.template match
        ret[alt] = if vars then API.mail.substitute(other.content,vars).content else other.content
  return ret



################################################################################

API.add 'mail/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.mail.test(this.queryParams.verbose)

API.mail.test = (verbose) ->
  console.log('Starting mail test') if API.settings.dev

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

  console.log('Ending mail test') if API.settings.dev

  return result
