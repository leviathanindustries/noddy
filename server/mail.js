
// an email forwarder
mail_template = new API.collection("mailtemplate");
mail_progress = new API.collection("mailprogress");

API.addRoute('mail/validate', {
  get: {
    action: function() {
      return {status: 'success', data: API.mail.validate(this.queryParams.email) };
    }
  }
});

API.addRoute('mail/send', {
  get: {
    action: function() {
      return {status: 'success', data: {info: 'Nothing here yet'} };
    }
  },
  post: {
    roleRequired:'root', // how to decide roles that can post mail remotely?
    action: function() {
      // TODO: check the groups the user is part of, and know which groups are allowed to send mail
      // TODO: get the json content and send it to sendmail
      //API._sendmail();
      return {}
    }
  }
});

// leaving this one in as deprecated, in use elsewhere
API.addRoute('sendmail/error', { post: { action: function() { API.mail.error(this.request.body,this.queryParams.token); return {}; } } });
API.addRoute('mail/error', {
  post: {
    action: function() {
      API.mail.error(this.request.body,this.queryParams.token);
      return {};
    }
  }
});

API.addRoute('mail/progress', {
  get: {
    action: function() {
      return mail_progress.search(this.bodyParams,this.queryParams);
    }
  },
  post: {
    action: function() {
      API.mail.progress(this.request.body,this.queryParams.token);
      return {};      
    }
  }
});

API.addRoute('mail/test', {
  get: {
    action: function() {
      return API.mail.test();
      //return {status: 'success', data: {} };
    }
  }
});



API.mail = {}

API.mail.send = function(opts,mail_url) {
  if ( !opts.from ) opts.from = API.settings.log.from;
  if ( !opts.to ) opts.to = API.settings.log.to; // also takes cc, bcc, replyTo, but not required. Can be strings or lists of strings
  if ( !opts.subject ) opts.subject = 'MAIL SENT WITHOUT SUBJECT!';
  
  if (opts.template) {
    var parts = API.mail.construct(opts.template,opts.vars);
    for ( var p in parts ) opts[p] = parts[p];
    delete opts.template;
  }
  // TODO what if list of emails to go with list of records?
  
  if ( !opts.text && !opts.html ) opts.text = opts.content ? opts.content : "";
  if (opts.content) delete opts.content;
  
  // can also take opts.headers
  // also takes opts.attachments, but not required. Should be a list of objects as per 
  // https://github.com/nodemailer/mailcomposer/blob/7c0422b2de2dc61a60ba27cfa3353472f662aeb5/README.md#add-attachments
  
  if (opts.smtp || opts.attachments === undefined) {
    delete opts.smtp;
    process.env.MAIL_URL = mail_url ? mail_url : API.settings.mail.url;
    API.log({msg:'Sending mail via mailgun SMTP',mail:opts});
    Email.send(opts);
    if (mail_url) process.env.MAIL_URL = API.settings.mail.url;
    return {};
  } else {
    var mailapi = 'https://api.mailgun.net/v3';
    var ms = opts.service ? API.settings.service[opts.service].mail : API.settings.mail;
    var url = mailapi + '/' + ms.domain + '/messages';
    delete opts.domain;
    if (typeof opts.to === 'object') opts.to = opts.to.join(',');
    API.log({msg:'Sending mail via mailgun API',mail:opts,url:url});
    try {
      var posted = HTTP.call('POST',url,{params:opts,auth:'api:'+ms.apikey});
      API.log({posted:posted});
      return posted;
    } catch(err) {
      API.log({msg:'Sending mail failed',error:err});
      return err;
    }
  }
}


API.mail.validate = function(email,apikey) {
  if (apikey === undefined) apikey = API.settings.mail.pubkey; // NOTE should use public key, not private key
  var u = 'https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(email) + '&api_key=' + apikey;
  try {
    var v = HTTP.call('GET',u);
    return v.data;
  } catch(err) {
    API.log({msg:JSON.stringify(err),notify:{subject:'Mailgun validate error'}});
    return {};
  }
}

API.mail.test = function() {
  return API.mail.send({
    from: Meteor.settings.mail.from,
    to: Meteor.settings.mail.to,
    subject: 'Test me via default POST',
    text: "hello",
    html: '<p><b>hello</b></p>'
    /*attachments:[{
      fileName: 'myfile.txt',
      filePath: '/home/cloo/att_test.txt'
    }]*/
  });
}

// mailgun progress webhook target
// https://documentation.mailgun.com/user_manual.html#tracking-deliveries
// https://documentation.mailgun.com/user_manual.html#tracking-failures
API.mail.progress = function(content,token) {
  // could do a token check here
  // could delete mail logs older than 1 week or so
  // if a failure event, notify someone
  if (content['message-id'] !== undefined && content['Message-Id'] === undefined) content['Message-Id'] = '<' + content['message-id'] + '>';
  mail_progress.insert(content);
  try {
    if (content.event === 'dropped') {
      var obj = {msg:'Mail service dropped email',error:JSON.stringify(content,undefined,2),notify:{msg:JSON.stringify(content,undefined,2),subject:'Mail service dropped email'}};
      if (content.domain !== API.settings.mail.domain) {
        for ( var s in API.settings.service) {
          if (API.settings.service[s].mail && API.settings.service[s].mail.domain === content.domain) {
            obj.notify.service = s;
            if (API.settings.service[s].mail.notify) {
              if (typeof API.settings.service[s].mail.notify === 'string') {
                obj.notify.to = API.settings.service[s].mail.notify;
              } else if (API.settings.service[s].mail.notify.dropped) {
                obj.notify.to = API.settings.service[s].mail.notify.dropped;
              }
            }
          }
        }
      }
      API.log(obj);
    }
  } catch(err) {}
}

API.mail.error = function(content,token) {
  var to;
  var mail_url;
  var subject = 'error dump';
  if (token) {
    try {
      to = API.settings.mail.error.tokens[token].to;
      mail_url = API.settings.mail.error.tokens[token].mail_url;
      subject = API.settings.mail.error.tokens[token].service + ' ' + subject;
      API.log('Sending error email for ' + API.settings.mail.error.tokens[token].service);
    } catch(err) {}
  }
  if (to !== undefined) {
    API.mail.send({
      from: API.settings.mail.from,
      to: to,
      subject: subject,
      text: JSON.stringify(content,undefined,2)
    },mail_url);
  }
}

API.mail.template = function(search,template) {
  if (template) {
    mail_template.insert(template);
  } else if (search) {
    if (typeof search === 'string') {
      // get the named template - could be filename without suffix
      // or could be look for filename
      var exists = mail_template.findOne(search);
      return exists ? exists : mail_template.findOne({template:search});
    } else {
      // search object, return matches, e.g. could be {service:'openaccessbutton'}
      var tmpls = mail_template.find(search).fetch();
      return tmpls.length === 1 ? tmpls[0] : tmpls;
    }
  } else {
    return mail_template.find().fetch();
  }
}

API.mail.substitute = function(content,vars,markdown) {
  var ret = {};
  // read variables IN to content
  for ( var v in vars ) {
    if (content.toLowerCase().indexOf('{{'+v+'}}') !== -1) {
      var rg = new RegExp('{{'+v+'}}','gi');
      content = content.replace(rg,vars[v]);
    }
  }
  if (content.indexOf('{{') !== -1) {
    var vs = ['subject','from','to','cc','bcc'];
    for ( var k in vs ) {
      var key = content.toLowerCase().indexOf('{{'+vs[k]) !== -1 ? vs[k] : undefined;
      if (key) {
        var keyu = content.indexOf('{{'+key.toUpperCase()) !== -1 ? key.toUpperCase() : key;
        var val = content.split('{{'+keyu)[1].split('}}')[0].trim();
        if (val) ret[key] = val;
        var kg = new RegExp('{{'+keyu+'.*?}}','gi');
        content = content.replace(kg,'');
      }
    }
  }
  ret.content = content;
  if (markdown) {
    // generate a text and an html element in ret
    ret.html = marked(ret.content);
    ret.text = ret.content.replace(/\[.*?\]\((.*?)\)/gi,"$1");
  }
  return ret;
}

API.mail.construct = function(tmpl,vars) {
  // if filename is .txt or .html look for the alternative too.
  // if .md try to generate a text and html option out of it
  var template = API.mail.template(tmpl);
  var md = template.filename.endsWith('.md');
  var ret = vars ? API.mail.substitute(template.content,vars,md) : {content: template.content};
  if (!md) {
    // look for the alternative too
    var alt;
    if (template.filename.endsWith('.txt')) {
      ret.text = ret.content;
      alt = 'html';
    } else if (template.filename.endsWith('.html')) {
      ret.html = ret.content;
      alt = 'txt';
    }
    try {
      var match = {filename:template.filename.split('.',[0])+'.'+alt};
      if (template.service) match.service = template.service;
      var other = API.mail.template(match);
      ret[alt] = vars ? API.mail.substitute(other.content,vars).content : other.content;
    } catch(err) {}
  }
  return ret;
}




