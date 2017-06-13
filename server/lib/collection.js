
// worth extending mongo.collection, or just not use it?
// https://stackoverflow.com/questions/34979661/extending-mongo-collection-breaks-find-method

API.collection = function (opts) {
  if (typeof opts === 'string') opts = {type:opts};
  if (opts.index === undefined && opts.type !== undefined) opts.index = API.settings.name ? API.settings.name : 'noddy';
  this._index = opts.index;
  this._type = opts.type;
  this._history = opts.history;
  this._replicate = opts.replicate;
  this._mapping = opts.mapping;
  this._route = '/' + opts.index + '/';
  if (opts.type) this._route += opts.type + '/';
  API.es.map(this._route,this._mapping);
};

API.collection.prototype.insert = function (obj) {
  if (!obj.createdAt) {
    obj.createdAt = Date.now();
    obj.created_date = moment(obj.createdAt,"x").format("YYYY-MM-DD HHmm");
  }
  var r = this._route;
  if (obj._id) r += obj._id;
  return API.es.insert(r, obj);
};

API.collection.prototype.update = function (obj) {
  var doc = API.es.get(this._route + obj._id);
  // TODO need error out if not found, or merge in the dot noted obj updates
  doc.updateAt = Date.now();
  doc.updated_date = moment(obj.createdAt,"x").format("YYYY-MM-DD HHmm");
  return API.es.insert(this._route + doc._id, doc);
};

API.collection.prototype.remove = function(uid) {
  if (uid) return API.es.delete(this._route + obj._id);
}

API.collection.prototype.search = function(qry,qp) {
  if (qp) {
    var rt = this._route + '/_search?';
    for ( var op in this.queryParams ) rt += op + '=' + this.queryParams[op] + '&';
    var data;
    if ( JSON.stringify(this.bodyParams).length > 2 ) data = this.bodyParams;
    return API.es.query('GET',rt,data);
  } else if (qry) {
    var dt;
    if ( JSON.stringify(qry).length > 2 ) dt = this.bodyParams;
    return API.es.query('POST',this._route + '/_search',dt);
  } else {
    return API.es.query('GET',this._route + '/_search');
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
    return API.es.query('POST',this._route,qry).hits.hits[0];
  } catch(err) {
    return [];
  }
}

