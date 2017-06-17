
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

API.collection.prototype.insert = function (obj) {
  if (!obj.createdAt) {
    obj.createdAt = Date.now();
    obj.created_date = moment(obj.createdAt,"x").format("YYYY-MM-DD HHmm");
  }
  var r = this._route;
  if (obj._id) r += obj._id;
  return API.es.call('POST',r, obj);
};

API.collection.prototype.update = function (obj) {
  var doc = API.es.call('GET',this._route + obj._id);
  // TODO need error out if not found, or merge in the dot noted obj updates
  doc.updateAt = Date.now();
  doc.updated_date = moment(obj.createdAt,"x").format("YYYY-MM-DD HHmm");
  return API.es.call('POST',this._route + doc._id, doc);
};

API.collection.prototype.remove = function(uid) {
  if (uid) return API.es.call('DELETE',this._route + uid);
}

API.collection.prototype.search = function(qry,qp) {
  if (qp) {
    var rt = this._route + '/_search?';
    for ( var op in qp ) rt += op + '=' + qp[op] + '&';
    var data;
    if ( JSON.stringify(qry).length > 2 ) data = qry;
    return API.es.call('GET',rt,data);
  } else if (qry) {
    var dt;
    if ( JSON.stringify(qry).length > 2 ) dt = qry;
    return API.es.call('POST',this._route + '/_search',dt);
  } else {
    return API.es.call('GET',this._route + '/_search');
  }
}

API.collection.prototype.count = function(qry,qp) { // TODO could be mongo-style queries, like findOne
  try {
    var res = this.search(qry,qp);
    return res.hits.total;
  } catch(err) {
    return 0;
  }
}

API.collection.prototype.find = function(q,opts) {
  if (typeof q === 'string') q = {'_id':q}
  var qry = {};
  // TODO build an ES query out of the possible incoming mongo queries
  // TODO handle options as well, like sort etc
  try {
    return API.es.call('POST',this._route,qry).hits.hits[0];
  } catch(err) {
    return [];
  }
}

