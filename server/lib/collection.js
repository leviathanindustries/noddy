
import Future from 'fibers/future';
import moment from 'moment';

// worth extending mongo.collection, or just not use it?
// https://stackoverflow.com/questions/34979661/extending-mongo-collection-breaks-find-method
// decided not to use it. If Mongo is desired in future, this collection object can be used to extend and wrap it

API.collection = function (opts) {
  if (typeof opts === 'string') opts = {type:opts};
  if (opts.index === undefined && opts.type !== undefined) opts.index = API.settings.es.index ? API.settings.es.index : (API.settings.name ? API.settings.name : 'noddy');
  this._index = opts.index;
  this._type = opts.type;
  this._history = opts.history;
  this._replicate = opts.replicate;
  this._route = '/' + opts.index + '/';
  if (opts.type) this._route += opts.type + '/';
  API.es.map(this._index,this._type); // only has effect if no mapping already
};

API.collection.prototype.map = function (mapping) {
  return API.es.map(this._index,this._type,mapping); // would overwrite any existing mapping
};

API.collection.prototype.insert = function (uid,obj,refresh) {
  if (typeof uid === 'string' && typeof obj === 'object') {
    obj._id = uid;
  } else if (typeof uid === 'object' && obj === undefined) {
    obj = uid;
  }
  if (!obj.createdAt) {
    obj.createdAt = Date.now();
    obj.created_date = moment(obj.createdAt,"x").format("YYYY-MM-DD HHmm");
  }
  var r = this._route;
  if (obj._id) r += obj._id;
  return API.es.call('POST',r, obj,refresh);
};

API.collection.prototype.update = function (qry,obj,refresh) {
  var rec;
  if (typeof qry === 'string' && qry.indexOf(' ') === -1) {
    var check = API.es.call('GET',this._route + qry);
    if (check.found !== false) rec = check;
  }
  delete obj._id; // just in case, can't replace the object ID.
  var rt = this._route;
  var update = function(doc) {
    for ( var k in obj ) {
      var upd = doc;
      var parts = k.split('.');
      var last = parts.pop();
      for ( var p in parts ) upd = upd[parts[p]];
      upd[last] = obj[k];
    }
    doc.updatedAt = Date.now();
    doc.updated_date = moment(obj.createdAt,"x").format("YYYY-MM-DD HHmm");
    API.es.call('POST',rt + doc._id, doc, refresh);
    return doc;
  }
  if (rec) {
    return update(rec);
  } else {
    return this.each(qry,update);
  }
};

API.collection.prototype.remove = function(qry) {
  if (typeof qry === 'number' || ( typeof qry === 'string' && qry.indexOf(' ') === -1 ) ) {
    var check = API.es.call('GET',this._route + qry);
    if (check.found !== false) {
      API.es.call('DELETE',this._route + qry);
      return true;
    }
  }
  var rt = this._route;
  var remove = function(doc) {
    API.es.call('DELETE',rt + doc._id);
  }
  return this.each(qry,remove);
}

API.collection.prototype.search = function(qry,qp,find) {
  if (find) {
    if (typeof find === 'object') {
      qp = {q:''}
      for ( var o in find ) {
        qp.q += qp.q.length === 0 ? '' : ' AND ';
        qp.q += o + ':' + (typeof find[o] === 'string' && find[o].indexOf(' ') !== -1 ? '"' + find[o] + '"' : find[o]);
      }
    } else {
      qp = {q:find}
    }
  }
  if (qp) {
    var rt = this._route + '/_search?';
    for ( var op in qp ) rt += op + '=' + qp[op] + '&';
    var data;
    if ( qry && JSON.stringify(qry).length > 2 ) data = qry;
    return API.es.call('GET',rt,data);
  } else if (qry && JSON.stringify(qry).length > 2) {
    return API.es.call('POST',this._route + '/_search',qry);
  } else {
    return API.es.call('GET',this._route + '/_search');
  }
}

API.collection.prototype.count = function(qry,qp,find) {
  try {
    var res = this.search(qry,qp,find);
    return res.hits.total;
  } catch(err) {
    return 0;
  }
}

API.collection.prototype.find = function(q) {
  if (typeof q === 'number' || ( typeof q === 'string' && q.indexOf(' ') === -1 ) ) {
    var check = API.es.call('GET',this._route + q);
    if (check.found !== false) return check._source;
  }
  try {
    var res = this.search(undefined,undefined,q).hits.hits[0];
    return res._source ? res._source : res.fields;
  } catch(err) {
    return false;
  }
}

API.collection.prototype.each = function(q,fn) {
  // TODO could use es.scroll here...
  var res = this.search(undefined,undefined,q);
  var count = res.hits.total;
  var counter = 0;
  while (counter < count) {
    for ( var r in res.hits.hits ) {
      var rec = res.hits.hits[r]._source ? res.hits.hits[r]._source : res.hits.hits[r].fields;
      fn(rec);
    }
    counter += res.hits.hits.length;
    if (counter < count) res = this.search(undefined,undefined,q); // TODO how to pass params like size and from?
  }
  return counter;
}


API.collection.test = function() {
  var result = {passed:true};
  var tc = new API.collection({index:API.settings.es.index + '_test',type:'collection'});
  var recs = [
    {_id:1,hello:'world'},
    {_id:2,goodbye:'world'},
    {goodbye:'world',hello:'sunshine'},
    {goodbye:'marianne',hello:'sunshine'}
  ];
  result.recs = recs;
  for ( var r in recs ) tc.insert(recs[r]);
  var future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.count = tc.count();
  result.passed = result.count === recs.length;
  result.search = tc.search();
  result.stringSearch = tc.search(undefined,undefined,'goodbye:"marianne"');
  result.passed = result.stringSearch.hits.total === 1;
  result.objectSearch = tc.search(undefined,undefined,{hello:'sunshine'});
  result.passed = result.objectSearch.hits.total === 2;
  result.idFind = tc.find(1);
  result.passed = typeof result.idFind === 'object';
  result.strFind = tc.find('goodbye:"marianne"');
  result.passed = typeof result.strFind === 'object';
  result.objFind = tc.find({goodbye:'marianne'});
  result.passed = typeof result.objFind === 'object';
  result.objFindMulti = tc.find({goodbye:'world'});
  result.passed = typeof result.objFindMulti === 'object';
  result.each = tc.each('goodbye:"world"',function() { return; });
  result.passed = result.each === 2;
  result.update = tc.update({hello:'world'},{goodbye:'world'});
  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.passed = typeof result.update === 'object' && result.update.goodbye === 'world';
  result.retrieveUpdated = tc.find({hello:'world'});
  result.passed = typeof result.retrieveUpdated === 'object' && result.retrieveUpdated.goodbye === 'world';
  result.goodbyes = tc.count('goodbye:"world"');
  result.passed = result.goodbyes === 3;
  result.remove1 = tc.remove(1);
  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.passed = result.remove1 === true;
  result.helloWorlds = tc.count({hello:'world'});
  result.passed = result.helloWorlds === 0;
  result.remove2 = tc.remove({hello:'sunshine'});
  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.passed = result.remove2 === 2;
  result.remaining = tc.count();
  result.passed = result.remaining === 2;
  return result;
}






