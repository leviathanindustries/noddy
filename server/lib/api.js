
import Future from 'fibers/future';
import moment from 'moment';
import fs from 'fs';
import marked from 'marked';

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
      var xid = this.request.headers['x-id'];
      if ( !xid ) xid = this.request.query.id;
      if ( !xid && this.request.query.email ) {
        u = API.accounts.retrieve(this.request.query.email);
        if (u) xid = u._id;
      }
      if ( !xid && this.request.query.username ) {
        u = API.accounts.retrieve(this.request.query.username);
        if (u) xid = u._id;
      }
      var xapikey = this.request.headers['x-apikey'];
      if ( !xapikey && this.request.query.apikey ) {
        xapikey = this.request.query.apikey;
      } else if ( !xapikey && this.request.query.api_key ) {
        xapikey = this.request.query.api_key;
      } else if ( !xapikey && this.request.body.apikey ) {
        xapikey = this.request.body.apikey;
      } else if ( !xapikey && this.request.body.api_key ) {
        xapikey = this.request.body.api_key;
      }
      if ( xid === undefined && xapikey ) {
        u = API.accounts.retrieve(xapikey);
        if(u) xid = u._id;
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
          u = Users.findOne({'emails.address':cookie.email,'security.resume.token':API.accounts.hash(cookie.resume),'security.resume.timestamp':cookie.timestamp});
          if (u) {
            API.log({msg:'User authenticated by cookie with timestamped resume token'});
          } else {
            u = Users.findOne({'emails.address':cookie.email,'security.fingerprint':cookie.fp,'security.resume.timestamp':cookie.timestamp});          
            if (u) API.log({msg:'User authenticated by cookie with timestamp and fingerprint'});
          }
          if (u) {
            xid = u._id;
            xapikey = u.api.keys[0].key;
          } else {
            API.log({msg:'POTENTIAL COOKIE THEFT!!! ' + cookie.userId});
          }
        } catch(err) {}
      }
      
      if ( xid === undefined ) xid = '';
      if ( xapikey === undefined ) xapikey = '';
      if (xid) API.log({msg:'user ' + xid + ' authenticated to API with key ' + xapikey});
      if (!API.settings.dev && u && u.roles && u.roles.__global_roles__ && u.roles.__global_roles__.indexOf('root') !== -1) {
        API.log({
          msg:'root user ' + xid + ' logged in to ' + this.request.url + ' from ' + this.request.headers['x-forwarded-for'] + ' ' + this.request.headers['x-real-ip'],
          notify: {
            subject: 'API root login ' + this.request.headers['x-real-ip']
          }
        });
      }
      return {
        userId: xid,
        token: xapikey // should perhaps better use API.accounts.hash(xapikey) and change which key the token is set to above
      };
    }
  }
});

API.settings = Meteor.settings;

API.log = function(opts) {
  try {
    // opts must contain msg and should contain level and error, and anything else should be stored as delivered
    if (typeof opts === 'string') opts = {msg: opts};
    if (!opts.level) opts.level = 'debug';
    opts.createdAt = Date.now();
    opts.created_date = moment(opts.createdAt,"x").format("YYYY-MM-DD HHmm");
    var logindex = Meteor.settings.es.index ? Meteor.settings.es.index + '_log' : Meteor.settings.name + '_log';
    var today = moment(opts.createdAt,"x").format("YYYYMMDD");
    var log;
    if (!API.es.exists(Meteor.settings.es.url + '/' + logindex + '/' + today)) {
      log = new API.collection({index:logindex,type:today});
      var future = new Future(); // a delay to ensure new log index is mapped
      setTimeout(function() { future.return(); }, 1000);
      future.wait();
    }
    var loglevels = ['all','trace','debug','info','warn','error','fatal','off'];
    var loglevel = API.settings.log && API.settings.log.level ? API.settings.log.level : 'all';
    if (loglevels.indexOf(loglevel) <= loglevels.indexOf(opts.level)) {
      if (loglevels.indexOf(loglevel) <= loglevels.indexOf('debug')) {
        console.log(opts.created_date);
        console.log(opts.msg);
        if (opts.error) console.log(opts.error);
      }
      // try to set some opts vars for which server the error is running on...
      try { opts.error = JSON.stringify(opts.error); } catch(err) {}
      try {
        log.insert(opts);
      } catch(err) {
        console.log('LOGGER ERROR INSERTION FAILED!!!')
      }
      if (opts.notify && API.settings.log.notify) {
        try {
          if (opts.notify === true) {
            opts.notify = {};
          } else if (typeof opts.notify === 'string') {
            // resolve the opts.notify to the dot noted settings object represented by the provided string
          }
          if (opts.notify.msg === undefined && opts.msg) opts.notify.msg = opts.msg;
          if (opts.notify.subject === undefined) opts.notify.subject = (Meteor.settings.name ? Meteor.settings.name + ' ' : '') + 'API log message';
          if (opts.notify.from === undefined) opts.notify.from = Meteor.settings.log.from ? Meteor.settings.log.from : 'alert@cottagelabs.com';
          if (opts.notify.to === undefined) opts.notify.to = Meteor.settings.log.to ? Meteor.settings.log.to : 'mark@cottagelabs.com';
        } catch(err) {
          console.log('LOGGER NOTIFICATION ERRORING OUT!!!');
        }
      }
    }
  } catch (err) {
    console.log('LOGGER IS ERRORING OUT!!!');
    console.log(err);
    console.log('LOGGER IS ERRORING OUT!!!');
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
  SyncedCron.config(Meteor.settings.cron.config ? Meteor.settings.cron.config : {utc:true});
  SyncedCron.start();
}

JsonRoutes.Middleware.use(function(req, res, next) {
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
        API.log({msg:'uploaded file received of length: ' + data.length});
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
