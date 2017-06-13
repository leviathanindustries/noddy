
// elasticsearch API

// because the logger uses ES to log logs, ES does not use the logger

// NOTE: if an index/type can be public, just make it public and have nginx route to it directly, saving app load.

var es = {
  get: {
    action: function() {
      var uid = this.request.headers['x-apikey'] ? this.request.headers['x-apikey'] : this.queryParams.apikey;
      if (JSON.stringify(this.urlParams) === '{}' && JSON.stringify(this.queryParams) === '{}') {
        return {status:"success"}
      } else {
        return API.es.action(uid, 'GET', this.urlParams, this.queryParams);
      }
    }
  },
  post: {
    action: function() { 
      var uid = this.request.headers['x-apikey'] ? this.request.headers['x-apikey'] : this.queryParams.apikey;
      return API.es.action(Meteor.userId, 'POST', this.urlParams, this.queryParams, this.request.body); 
    }
  },
  put: {
    authRequired: true,
    action: function() { return API.es.action(Meteor.userId, 'PUT', this.urlParams, this.queryParams, this.request.body); }
  },
  delete: {
    authRequired: true,
    action: function() { return API.es.action(Meteor.userId, 'DELETE', this.urlParams, this.queryParams, this.request.body); }
  }
}

API.addRoute('es', es);
API.addRoute('es/:ra', es);
API.addRoute('es/:ra/:rb', es);
API.addRoute('es/:ra/:rb/:rc', es);
API.addRoute('es/:ra/:rb/:rc/:rd', es);

API.es = {};

if (!Meteor.settings || !Meteor.settings.es) {
  console.log('WARNING - ELASTICSEARCH SEEMS TO BE REQUIRED BUT SETTINGS HAVE NOT BEEN PROVIDED.');  
} else {
  try {
    var s = Meteor.http.call('GET',Meteor.settings.es.url);
  } catch(err) {
    console.log('ELASTICSEARCH INSTANCE AT ' + Meteor.settings.es.url + ' APPEARS TO BE UNREACHABLE. SHUTTING DOWN.');
    console.log(err);
    process.exit(-1);
  }
}

API.es.action = function(uid,action,urlp,params,data) {
  var rt = '';
  for ( var up in urlp ) rt += '/' + urlp[up];
  if (params) {
    rt += '?';
    for ( var op in params ) rt += op + '=' + params[op] + '&';
  }
  var user = uid ? API.accounts.retrieve(uid) : undefined;
  var allowed = user && API.accounts.auth('root',user) ? true : false; // should the root user get access to everything or only the open routes?
  // NOTE that the call to this below still requires user auth on PUT and DELETE, so there cannot be any public allowance on those
  if (!allowed) {
    var auth = API.settings.es.auth;
    if (auth && auth[urlp.ra]) {
      auth = auth[urlp.ra];
      if (auth[urlp.rb]) {
        auth = auth[urlp.rb]
        if (auth[urlp.rc]) auth = auth[urlp.rc];
      }
    }
    if (auth === true) allowed = true; // if the whole index or whole type or endpoint points to true, it is public
  }
  if (user && !allowed) {
    var ort = urlp.ra;
    if (urlp.rb) ort += '_' + urlp.rb;
    if ( ( action === 'GET' || ( action === 'POST' && urlp.rc === '_search' ) ) && API.accounts.auth(ort+'.read',user)) {
      allowed = true;
    } else if ( ( action === 'POST' || action === 'PUT' ) && API.accounts.auth(ort+'.edit',user)) {
      allowed = true;
    } else if (action === 'DELETE' && API.accounts.auth(ort+'.owner'),user) {
      allowed = true;
    }
  }
  if (allowed) {
    return API.es.call(action,rt,data);
  } else {
    return {statusCode:401,body:{status:"error",message:"401 unauthorized"}}
  }
}

// TODO add other actions in addition to map, for exmaple _reindex would be useful
// how about _alias? And check for others too, and add here

API.es.map = function(index,type,mapping,url) {
  if (url === undefined) url = Meteor.settings.es.url;
  try {
    Meteor.http.call('HEAD',url + '/' + index);
  } catch(err) {
    var pt = Meteor.settings.es.version && Meteor.settings.es.version > 5 ? Meteor.http.call('PUT',url + '/' + index) : Meteor.http.call('POST',url + '/' + index);
  }
  var maproute = API.settings.es.version > 1 ? index + '/_mapping/' + type : maproute = index + '/' + type + '/_mapping';
  if ( mapping === undefined ) {
    try {
      Meteor.http.call('HEAD',url + '/' + maproute);      
    } catch(err) {
      mapping = Meteor.http.call('GET','http://static.cottagelabs.com/mapping.json').data;
    }
  }
  if (mapping) {
    return Meteor.http.call('PUT',url + '/' + maproute,{data:mapping}).data;
  }
}

API.es.call = function(action,route,data,url) {
  if (url === undefined) url = API.settings.es.url;
  if (route.indexOf('/') !== 0) route = '/' + route;
  var routeparts = route.substring(1,route.length).split('/');
  if (route.indexOf('/_') === -1 && routeparts.length >= 1 && ( action === 'POST' || action === 'PUT' ) ) API.es.map(routeparts[0],routeparts[1],url);
  var opts = {};
  if (data) opts.data = data;
  if (route.indexOf('source') !== -1 && route.indexOf('random=true') !== -1) {
    try {
      var fq = {
        function_score : {
          query : undefined, // set below
          random_score : {}// "seed" : 1376773391128418000 }
        }
      }
      route = route.replace('random=true','');
      if (route.indexOf('seed=') !== -1) {
        var seed = route.split('seed=')[0].split('&')[0];
        fq.function_score.random_score.seed = seed;
        route = route.replace('seed='+seed,'');
      }
      var rp = route.split('source=');
      var start = rp[0];
      var qrp = rp[1].split('&');
      var qr = JSON.parse(decodeURIComponent(qrp[0]));
      var rest = qrp.length > 1 ? qrp[1] : '';
      if (qr.query.filtered) {
        fq.function_score.query = qr.query.filtered.query;
        qr.query.filtered.query = fq
      } else {
        fq.function_score.query = qr.query;
        qr.query = fq;
      }
      qr = encodeURIComponent(JSON.stringify(qr));
      route = start + 'source=' + qr + '&' + rest;
    } catch(err) {}
  }
  var ret;
  try {
    ret = Meteor.http.call(action,url+route,opts).data;
  } catch(err) {
    // TODO check for various types of ES error - for some we may want retries, others may want to trigger specific log alerts
    console.log(err);
    console.log(action);
    console.log(url+route);
    console.log(opts);
    ret = {info: 'the call to es returned an error, but that may not necessarily be bad', err:err}
  }
  return ret;
}

