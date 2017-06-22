
import Future from 'fibers/future';
import moment from 'moment';

// api login example:
// curl -X GET "http://api.cottagelabs.com/accounts" -H "x-id: vhi5m4NJbJF7bRXqp" -H "x-apikey: YOURAPIKEYHERE"
// curl -X GET "http://api.cottagelabs.com/accounts?id=vhi5m4NJbJF7bRXqp&apikey=YOURAPIKEYHERE"

API = new Restivus({
  version: '',
  defaultHeaders: { 'Content-Type': 'application/json; charset=utf-8' },
  prettyJson: true,
  auth: {
    token: 'api.keys.key', // should perhaps be hashedToken and change below to pass a hashed value instead
    user: function () {
      var u;
      var xid = this.request.headers['x-id'] ? this.request.headers['x-id'] : this.request.query.id;
      if ( !xid && ( this.request.query.email || this.request.query.username ) ) {
        u = API.accounts.retrieve( ( this.request.query.email ? this.request.query.email : this.request.query.username ) );
        if (u) xid = u._id;
      }
      var xapikey = this.request.headers['x-apikey'] ? this.request.headers['x-apikey'] : this.request.query.apikey;
      if ( xid === undefined && xapikey ) {
        u = API.accounts.retrieve(xapikey);
        if (u) xid = u._id;
      }

      if (!xid && this.request.headers.cookie && API.settings.cookie && API.settings.cookie.name) {
        var name = API.settings.cookie.name + "=";
        var ca = this.request.headers.cookie.split(';');
        var cookie;
        try {
          cookie = JSON.parse(decodeURIComponent(function() {
            for(var i=0; i<ca.length; i++) {
              var c = ca[i];
              while (c.charAt(0)==' ') c = c.substring(1);
              if (c.indexOf(name) != -1) return c.substring(name.length,c.length);
            }
            return "";
          }()));
          u = Users.find({'emails.address':cookie.email,'security.resume.token':API.accounts.hash(cookie.resume),'security.resume.timestamp':cookie.timestamp});
          if (u) {
            xid = u._id;
            xapikey = u.api.keys[0].key;
          }
        } catch(err) {}
      }
      
      if ( xid === undefined ) xid = '';
      if ( xapikey === undefined ) xapikey = '';
      if (API.settings.log.root && u && u.roles && u.roles.__global_roles__ && u.roles.__global_roles__.indexOf('root') !== -1) {
        API.log({
          msg:'root user logged in to ' + this.request.url + ' from ' + this.request.headers['x-forwarded-for'] + ' ' + this.request.headers['x-real-ip'],
          notify: {
            subject: 'API root login ' + this.request.headers['x-real-ip']
          }
        });
      } else if (xid) {
        API.log({msg:'user ' + xid + ' authenticated to API with key ' + xapikey});
      }
      return {
        userId: xid,
        token: xapikey // should perhaps better use API.accounts.hash(xapikey) and change which key the token is set to above
      };
    }
  }
});

API.settings = Meteor.settings;

API.log = function(opts,lvl) {
  try {
    // opts must contain msg and should contain level and error, and anything else should be stored as delivered
    if (typeof opts === 'string') opts = {msg: opts};
    if (lvl && typeof lvl === 'string') opts.level = lvl;
    if (!opts.level) opts.level = 'debug';
    opts.createdAt = Date.now();
    opts.created_date = moment(opts.createdAt,"x").format("YYYY-MM-DD HHmm");
    var logindex = API.settings.es.index ? API.settings.es.index + '_log' : API.settings.name + '_log';
    var today = moment(opts.createdAt,"x").format("YYYYMMDD");
    var logexisted = API.es.exists(API.settings.es.url + '/' + logindex + '/' + today);
    var log = new API.collection({index:logindex,type:today});
    if (!logexisted) {
      var future = new Future(); // a delay to ensure new log index is mapped
      setTimeout(function() { future.return(); }, 1000);
      future.wait();
    }
    var loglevels = ['all','trace','debug','info','warn','error','fatal','off'];
    var loglevel = API.settings.log && API.settings.log.level ? API.settings.log.level : 'all';
    if (loglevels.indexOf(loglevel) <= loglevels.indexOf(opts.level)) {
      if (loglevels.indexOf(loglevel) <= loglevels.indexOf('debug')) console.log(opts);
      // try to set some opts vars for which server the error is running on...
      try { opts.error = JSON.stringify(opts.error); } catch(err) {}
      try {
        log.insert(opts);
      } catch(err) {
        console.log('LOGGER ERROR INSERTION FAILED!!!');
        console.log(opts);
        console.log(err);
      }
      if (opts.notify && API.settings.log.notify) {
        try {
          if (opts.notify === true) {
            opts.notify = {};
          } else if (typeof opts.notify === 'string') {
            if (opts.notify.indexOf('@') !== -1) {
              opts.notify = {to:opts.notify};
            } else {
              opts.notify = false;
              var pts = opts.notify.split('.');
              var srv = pts[0];
              var nt = pts[1];
              if (API.settings.service[srv]) {
                var svs = API.settings.service[srv];
                var df = svs.mail ? svs.mail : API.settings.mail;
                var on = df.mail.notify && df.mail.notify[nt] ? df.mail.notify[nt] : df;
                if (opts.notify.disabled) {
                  opts.notify = false;
                } else {
                  for ( var mn in on ) df[mn] = on[mn];
                  opts.notify = df;
                }                
              }
            }
          }
          if (opts.notify) {
            if (opts.notify.msg === undefined && opts.msg) opts.notify.msg = opts.msg;
            if (opts.notify.text === undefined) opts.notify.text = opts.notify.msg;
            if (opts.notify.subject === undefined) opts.notify.subject = (API.settings.name ? API.settings.name + ' ' : '') + 'API log message';
            if (opts.notify.from === undefined) opts.notify.from = API.settings.log.from ? API.settings.log.from : 'alert@cottagelabs.com';
            if (opts.notify.to === undefined) opts.notify.to = API.settings.log.to ? API.settings.log.to : 'mark@cottagelabs.com';
            API.mail.send(opts.notify);
          }
        } catch(err) {
          console.log('LOGGER NOTIFICATION ERRORING OUT!!!');
        }
      }
    }
  } catch (err) {
    console.log('LOGGER IS ERRORING OUT!!!');
    console.log(err);
  }
}

API.addRoute('/', {
  get: {
    action: function() {
      return {name:(API.settings.name ? API.settings.name : 'API'),version:(API.settings.version ? API.settings.version : "0.0.1")}
    }
  }
});

if (API.settings.cron && API.settings.cron.enabled) {
  // TODO should rewrite syncedcron as it falls over sometimes and is no longer supported
  // TODO should have a cron job to run API.test() regularly
  API.log('Cron starting.');
  SyncedCron.config(API.settings.cron.config ? API.settings.cron.config : {utc:true});
  SyncedCron.start();
}

JsonRoutes.Middleware.use(function(req, res, next) {
  if (API.settings.log.connections) {
    try {
      API.log({request:{
        url: req.url,
        originalUrl: req.originalUrl,
        headers: req.headers,
        query: req.query,
        body: req.body
      }});
    } catch(err) {
      console.log('API LOGGING OF INCOMING QUERIES IS FAILING!');
      console.log(err);
    }
  }
  if (req.headers && req.headers['content-type'] && req.headers['content-type'].match(/^multipart\/form\-data/)) {
    var Busboy = Meteor.npmRequire('busboy');
    var busboy = new Busboy({headers: req.headers});
    req.files = [];

    busboy.on('file', function(fieldname, file, filename, encoding, mimetype) {
      var uploadedFile = {
        filename,
        mimetype,
        encoding,
        fieldname,
        data: null
      };

      var buffers = [];
      file.on('data', function(data) {
        API.log({msg:'File received',length:data.length,filename:filename});
        buffers.push(data);
      });
      file.on('end', function() {
        uploadedFile.data = Buffer.concat(buffers);
        req.files.push(uploadedFile);
      });
    });

    busboy.on("field", function(fieldname, value) {
      req.body[fieldname] = value;
    });
    
    busboy.on('finish', function() {
      next();
    });

    req.pipe(busboy);
    return;
  }
  next();
});
