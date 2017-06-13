
// elasticsearch API

// handle authn and authz for es indexes and types (and possibly backup triggers)
// NOTE: if an index/type can be public, just make it public and have nginx route to it directly, saving app load.

if (!Meteor.settings || !Meteor.settings.es) {
  API.log('WARNING - ELASTICSEARCH SEEMS TO BE REQUIRED BUT SETTINGS HAVE NOT BEEN PROVIDED.');  
} else {
  try {
    var s = Meteor.http.call('GET',Meteor.settings.es.url);
  } catch(err) {
    API.log({msg:'ELASTICSEARCH INSTANCE AT ' + Meteor.settings.es.url + ' APPEARS TO BE UNREACHABLE. SHUTTING DOWN.', error:err});
    process.exit(-1);
  }
}

API.addRoute('es/import', {
  post: {
    roleRequired: 'root', // decide which roles should get access - probably within the function, depending on membership of corresponding groups
    action: function() {
      return {status: 'success', data: API.es.import(this.request.body)};
    }
  }
});

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

if (API.settings.dev && !API.settings.es.prefix) API.log("NOTE, settings indicate a dev setup, but there is no ES prefix set. If ES url is same as production, this means that dev actions could write into production indexes...");

API.es = {};

API.es.action = function(uid,action,urlp,params,data) {
  var rt = '';
  for ( var up in urlp ) rt += '/' + urlp[up];
  if (params) {
    rt += '?';
    for ( var op in params ) rt += op + '=' + params[op] + '&';
  }
  // unless the user is in global root group, check that the url is in the allowed routes
  // also check that the user is in the necessary group to access the route
  // so there needs to be an elasticsearch group that gives user permissions on certain roles, like blocked_GET, or something like that
  var user = uid ? API.accounts.retrieve(uid) : undefined;
  var allowed = user && API.accounts.auth('root',user) ? true : false; // should the root user get access to everything or only the open routes?
  // NOTE that the call to this below still requires user auth on PUT and DELETE, so there cannot be any public allowance on those
  if (!allowed) {
    var open = API.settings.es.routes;
    for ( var o in open ) {
      if (!allowed && rt.indexOf(o) === 0) {
        var ort = open[o];
        if (ort.public) {
          allowed = true;
        } else if (user) {
          // if part of the route is listed in the list of open routes, then a user who is in a group matching
          // the name of the route without slashes will have some permissions on that index
          if (action === 'GET' && API.accounts.auth(ort+'.read',user)) {
            allowed = true; // any user in the group can GET
          } else if (action === 'POST' && API.accounts.auth(ort+'.edit',user)) {
            allowed = true;
          } else if (action === 'PUT' && API.accounts.auth(ort+'.publish',user)) {
            allowed = true;
          } else if (action === 'DELETE' && API.accounts.auth(ort+'.owner'),user) {
            allowed = true;
          }
          // also the settings for the route may declare actions and groups that can perform that action
          // other settings could go in there too, but this has yet to be implemented
        }
      }
    }
  }
  if (allowed) {
    if (urlp.rc === '_facet' && urlp.rd !== undefined) {
      return API.es.facet(urlp.ra,urlp.rb,urlp.rd);
    } else {
      return API.es.query(action,rt,data);
    }
  } else {
    return {statusCode:401,body:{status:"error",message:"401 unauthorized"}}
  }
}

API.es.exists = function(route,url) {
  if ( route.indexOf('/') !== 0 ) route = '/' + route;
  var routeparts = route.substring(1,route.length).split('/');
  var esurl = url ? url : API.settings.es.url;
  var db = esurl + '/';
  if (API.settings.es.prefix) db += API.settings.es.prefix;
  db += routeparts[0];
  try {
    var dbexists = Meteor.http.call('HEAD',db);
    return true;
  } catch(err) {
    return false;
  }  
}

// TODO add other actions in addition to map, for exmaple _reindex would be useful
// how about _alias? And check for others too, and add here

API.es.map = function(route,map,url) {
  if ( map === undefined ) map = Meteor.http.call('GET','http://static.cottagelabs.com/mapping.json').data;
  if ( route.indexOf('/') !== 0 ) route = '/' + route;
  var routeparts = route.substring(1,route.length).split('/');
  var esurl = url ? url : API.settings.es.url;
  var db = esurl + '/';
  if (API.settings.es.prefix) db += API.settings.es.prefix;
  db += routeparts[0];
  API.log('creating es mapping for ' + db + '/' + routeparts[1]);
  try {
    var dbexists = Meteor.http.call('HEAD',db);
  } catch(err) {
    if (Meteor.settings.es.version && Meteor.settings.es.version > 5) {
      Meteor.http.call('PUT',db);
    } else {
      Meteor.http.call('POST',db);
    }
  }
  var maproute = db + '/_mapping/' + routeparts[1];
  if ( API.settings.es.version < 1 ) maproute = db + '/' + routeparts[1] + '/_mapping';
  try {
    return Meteor.http.call('PUT',maproute,{data:map});
  } catch(err) {
    API.log({msg:'PUT mapping to ' + maproute + ' failed.',error:err});
  }
}

API.es.terms = function(index,type,key,url) {
  //API.log('Performing elasticsearch facet on ' + index + ' ' + type + ' ' + key);
  var size = 100;
  var esurl = url ? url : API.settings.es.url;
  var opts = {data:{query:{"match_all":{}},size:0,facets:{}}};
  opts.data.facets[key] = {terms:{field:key,size:size}}; // TODO need some way to decide if should check on .exact?
  try {
    if (API.settings.es.prefix) index = API.settings.es.prefix + index;
    var ret = Meteor.http.call('POST',esurl+'/'+index+'/'+type+'/_search',opts);
    return ret.data.facets[key].terms;
  } catch(err) {
    return {info: 'the call to es returned an error', err:err}
  }
}

API.es.query = function(action,route,data,url) {
  if (url) API.log('To url ' + url);
  var esurl = url ? url : API.settings.es.url;
  if (route.indexOf('/') !== 0) route = '/' + route;
  if (API.settings.es.prefix && route !== '/_status' && route !== '/_stats' && route !== '/_cluster/health') route = '/' + API.settings.es.prefix + route.substring(1,route.length);
  //API.log('Performing elasticsearch ' + action + ' on ' + route);
  var routeparts = route.substring(1,route.length).split('/');
  if (route.indexOf('/_') === -1 && routeparts.length >= 1 && action !== 'DELETE' && action !== 'GET') {
    try {
      var turl = esurl + '/' + routeparts[0];
      if (routeparts.length > 1) turl += '/' + routeparts[1];
      var exists = Meteor.http.call('HEAD',turl);
    } catch(err) {
      API.es.map(route);
    }
  }
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
    ret = Meteor.http.call(action,esurl+route,opts).data;
  } catch(err) {
    // TODO check for various types of ES error - for some we may want retries, others may want to trigger specific log alerts
    API.log(err);
    ret = {info: 'the call to es returned an error, but that may not necessarily be bad', err:err}
  }
  return ret;
}

API.es.get = function(route,url) {
  return API.es.query('GET',route,undefined,url);
}
API.es.insert = function(route,data,url) {
  return API.es.query('POST',route,data,url);
}
API.es.delete = function(route,url) {
  return API.es.query('DELETE',route,undefined,url);
}

API.es.import = function(data,format,index,type,url,bulk,mappings,ids) {
  API.log('starting es import');
  if (format === undefined) format = 'es';
  if (ids === undefined) ids = 'es';
  if (bulk === undefined) {
    bulk = 10000;
  } else if (bulk === false) {
    bulk = 1;
  }
  if (url === undefined) url = API.settings.es.url;
  var rows = format === 'es' ? data.hits.hits : data;
  if (!Array.isArray(rows)) rows = [rows];
  var recs = [];
  var counter = 0;
  var failures = 0;
  var dump = '';
  // TODO if mappings are provided, load them first
  if (mappings) {
    for ( var m in mappings ) {
      var madr = url + '/' + m;
      var map = mappings[m] ? mappings[m] : undefined;
      API.es.map(madr,map);
    }
  }
  var bulkinfo = [];
  for ( var i in rows ) {
    var rec;
    if (format === 'es') {
      rec = rows[i]._source !== undefined ? rows[i]._source : rows[i]._fields;
    } else {
      rec = rows[i];
    }
    var tp = type !== undefined ? type : rows[i]._type;
    var idx = index !== undefined ? index : rows[i]._index;
    if (API.settings.es.prefix) {
      idx = API.settings.es.prefix + idx;
      if (rows[i]._index) rows[i]._index = idx;
    }
    var id, addr;
    if (ids) {
      id = ids === true || ids === 'es'? rows[i]._id : rec[ids];
    }
    if ( bulk === 1 ) {
      API.log('es import doing singular insert');
      addr = url + '/' + idx + '/' + tp;
      if (id !== undefined) addr += '/' + id;
      try {
        Meteor.http.call('POST',addr,{data:rec});
      } catch(err) {
        failures += 1;
      }
    } else {
      counter += 1;
      var meta = {"index": {"_index": idx, "_type":tp}};
      if (id !== undefined) meta.index._id = id;
      dump += JSON.stringify(meta) + '\n';
      dump += JSON.stringify(rec) + '\n';
      if ( (counter === bulk || i == (rows.length - 1) ) && idx && tp ) { // NOTE THIS: i as an iterator is a string not a number, so === would return false...
        API.log('bulk importing to es');
        addr = url + '/_bulk';
        var b = API.post(addr,dump);
        bulkinfo.push(b);
        dump = '';
        counter = 0;
      }
    }
  }
  API.log(rows.length + ' ' + failures);
  return {records:rows.length,failures:failures,bulk:bulkinfo};
}




