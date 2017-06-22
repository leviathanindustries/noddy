
import moment from 'moment';

limit = new API.collection("limit");

API.addRoute('limit/test', {
  get: {
    roleRequired: 'root',
    action: function() {
      return API.limit.test();
    }
  }
});

API.addRoute('limit/status', {
  get: {
    action: function() {
      return {status:'success',data: API.limit.status()};
    }
  }
});



API.limit = {};

API.limit.do = function(limit,method,name,args,tags,meta) {
  var now = Date.now();
  //limit.remove('expires:<now');
  var previous = limit.find({name:name,tags:tags,expires:'>'+now},{sort:{createdAt:-1}}); // TODO review the gt use in obj, and how to pass sort
  var expires = previous ? previous.expires + limit : now + limit;
  // NOTE moment formats to system time, which I note is different on the docker boxes (UTC) than the main box (BST)
  // this does not affect the running of jobs because they check against the now unix timestamp which is UTC
  // but when viewing the limit status, it can look odd because the formatted dates come out with an hour difference sometimes
  // can fix this with moment.utc() if desirable, but not necessary - would look better in one way being uniform, but perhaps 
  // worse in being uniformly out of sync with UK viewiers for half the year (and it is only admins who look at it anyway)
  // https://momentjs.com/docs/#/displaying/
  var expires_date = moment(expires,"x").format("YYYY-MM-DD HHmm:ss.SSS");
  var created_date = moment(now,"x").format("YYYY-MM-DD HHmm:ss.SSS");
  var lim = {limit:limit,name:name,args:args,tags:tags,expires:expires,expires_date:expires_date,createdAt:now,created_date:created_date};
  limit.insert(lim);
  API.log('limiting next ' + name + ' at ' + created_date + ' to ' + expires_date);

  if (previous) {
    var delay = previous.expires - now;
    var future = new Future();
    setTimeout(function() { future.return(); }, delay);
    future.wait();
  }
  var res = method.apply(this,args);
  return meta ? {meta:lim,result:res} : res;
};

API.limit.status = function() {
  var s = { count: limit.count() };
  if (s.count) {
    s.last = limit.find({expires:'<'+Date.now()},{sort:{createdAt:-1}}).expires_date; // TODO check use of lt in obj, and passing sort options
    var latest = limit.find({},{sort:{createdAt:-1}}); // TODO need a search all, and pass in sort order, and return top res
    s.latest = {time:latest.expires_date,name:latest.name};
  }
  return s;
}

// TODO think of a good way to test this

