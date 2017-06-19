
import { Random } from 'meteor/random';

Users = new API.collection({type:"users",history:true});
loginCodes = new API.collection("logincodes");

API.addRoute('accounts', {
  get: {
    authRequired:true,
    action: function() {
      if ( API.accounts.auth('root', this.user) ) {
        return Users.search(this.bodyParams,this.queryParams);
      } else {
        return {count: Users.count() };
      }
    }
  },
  post: {
    roleRequired:'root',
    action: function() {
      return Users.search(this.bodyParams,this.queryParams);
    }
  }
});
API.addRoute('accounts/xsrf', {
  post: { authRequired: true, action: function() { return API.accounts.xsrf(this.user); } }
});
API.addRoute('accounts/token', {
  get: { action: function() { return API.accounts.token(this.queryParams.email,this.queryParams.url,this.queryParams.service,this.queryParams.fingerprint); } },
  post: { action: function() { return API.accounts.token(this.bodyParams.email,this.bodyParams.url,this.bodyParams.service,this.bodyParams.fingerprint); } }
});
API.addRoute('accounts/login', {
  post: { action: function() { return API.accounts.login(this.bodyParams.email,this.bodyParams.token,this.bodyParams.hash,this.bodyParams.fingerprint,this.request) } }
});
API.addRoute('accounts/logout', {
  post: { authRequired: true, action: function() { return API.accounts.logout(this.userId) } }
});
API.addRoute('accounts/logout/:id', {
  post: { roleRequired: 'root', action: function() { return API.accounts.logout(this.urlParams.id) } }
});

API.addRoute('accounts/:id', {
  get: {
    authRequired: true,
    action: function() {
      var u = API.accounts.retrieve(this.urlParams.id);
      return u ? API.accounts.details(u._id,this.user) : {statusCode: 404, body:'404 NOT FOUND' };
    }
  },
  post: {
    authRequired: true,
    action: function() {
      if (!this.queryParams.xsrf || !API.accounts.xsrf(this.user,this.queryParams.xsrf)) return {statusCode: 401, body: {}}
      var u = API.accounts.retrieve(this.urlParams.id);
      if (!u) {
        return {statusCode: 404, body:'404 NOT FOUND' };
      } else {
        var updated = API.accounts.update(u._id,this.user,this.request.body);
        return updated ? {status: 'success'} : {status: 'error'};
      }
    }
  },
  put: {
    authRequired: true,
    action: function() {
      if (!this.queryParams.xsrf || !API.accounts.xsrf(this.user,this.queryParams.xsrf)) return {statusCode: 401, body: {}}
      var u = API.accounts.retrieve(this.urlParams.id);
      if (!u) {
        return {statusCode: 404, body:'404 NOT FOUND' };
      } else {
        var updated = API.accounts.update(u._id,this.user,this.request.body,true);
        return updated ? {status: 'success'} : {status: 'error'};
      }
    }
  },
  delete: {
    authRequired: true,
    action: function() {
      if (!this.queryParams.xsrf || !API.accounts.xsrf(this.user,this.queryParams.xsrf)) return {statusCode: 401, body: {}}
      var u = API.accounts.retrieve(this.urlParams.id);
      if (!u) {
        return {statusCode: 404, body:'404 NOT FOUND' };
      } else {
        var deleted = API.accounts.delete(u._id,this.user,this.urlParams.service);
        return deleted ? {status: 'success'} : {status: 'error'};
      }
    }
  }
});

API.addRoute('accounts/:id/auth/:grouproles', {
  get: {
    action: function() {
      var u = API.accounts.retrieve(this.urlParams.id);
      var authd = false;
      var rset = this.urlParams.grouproles.split(',');
      for (var r in rset) {
        authd = API.accounts.auth(rset[r], u);
      }
      if ( authd ) {
        return {status: 'success', data: {auth: authd} };
      } else {
        return {statusCode: 404, body: {status: 'success', data: {auth: false} }};
      }
    }
  }
});
API.addRoute('accounts/:id/roles/:grouprole', {
  post: {
    authRequired: true,
    action: function() {
      if (!this.queryParams.xsrf || !API.accounts.xsrf(this.user,this.queryParams.xsrf)) return {statusCode: 401, body: {}}
      // group and role must not contain . or , because . is used to distinguish group from role, and comma to list them
      // what other characters should be allowed / blocked from groups and roles?
      var grp, role;
      var grpts = this.urlParams.grouprole.split('.');
      if (grpts.length !== 2) return {status: 'error', data: 'grouprole param must be of form group.role'}
      grp = grpts[0];
      role = grpts[1];

      var auth = API.accounts.auth(grp + '.auth', this.user);
      if ( role === 'public' ) auth = true;
      if ( auth ) {
        return API.accounts.addrole(this.urlParams.id,grp,role);
      } else {
        return {
          statusCode: 403,
          body: {status: 'error', data: {message: 'you do not have permission to alter users in this role'} }
        };
      }
    }
  },
  delete: {
    authRequired: true,
    action: function() {
      if (!this.queryParams.xsrf || !API.accounts.xsrf(this.user,this.queryParams.xsrf)) return {statusCode: 401, body: {}}
      var grp, role;
      var grpts = this.urlParams.grouprole.split('.');
      if (grpts.length !== 2) return {status: 'error', data: 'grouprole param must be of form group.role'}
      grp = grpts[0];
      role = grpts[1];
      var auth = API.accounts.auth(grp + '.auth', this.user);
      if ( role === 'public' ) auth = true;
      if ( auth ) {
        return API.accounts.removerole(this.urlParams.id,grp,role);
      } else {
        return {
          statusCode: 403,
          body: {status: 'error', data: {message: 'you do not have permission to alter users in this role'} }
        };
      }
    }
  }
});




function generate_random_code(length,set) {
  if (length === undefined) length = 7;
  if (set === undefined) set = "23456789abcdef";
  var random_hash = "";
  for ( ; random_hash.length < length; ) {
    var chr = Random.choice(set);
    if ( random_hash.length !== 0 && chr === random_hash.charAt(random_hash.length-1) ) continue;
    random_hash += chr;
  }
  return random_hash;
}

API.accounts = {};

// receive a device fingerprint and perhaps some settings (e.g. to make it a registered / named device)
API.accounts.fingerprint = function(uacc,fingerprint) {
  // TODO fingerprint should go in devices area of account, with mutliple fingerprints and useful info possible
  // perhaps if fingerprint is not yet in devices list, a notification should be sent to the user account?
  // for now just sets the fingerprint
  var set = {}
  if (uacc.security) {
    set['security.fingerprint'] = fingerprint;
  } else {
    set.security = {fingerprint:fingerprint}
  }
  Users.update(uacc._id, set);
}

API.accounts.xsrf = function(uacc,xsrf) {
  if (xsrf) {
    var match = uacc.security.xsrf === xsrf;
    Users.update(uacc._id, {'security.xsrf':undefined});
    return match;
  } else {
    // for actions that can edit data or execute dangerous things, the frontend can ask for an xsrf nonce first
    // the nonce should then be returned with the data change
    xsrf = Random.hexstring(30);
    Users.update(uacc._id, {'security.xsrf':API.accounts.hash(xsrf)});
    return {xsrf:xsrf};
  }
}

API.accounts.token = function(email,url,service,fingerprint,send) {
  var opts;
  try {
    opts = API.settings.service[service].accounts;
  } catch(err) {
    var svn;
    for ( var sv in API.settings.service ) {
      if (API.settings.service[sv].accounts) {
        svn = sv;
        opts = API.settings.service[sv].accounts;
      }
    }
  }
  if (!opts) return {};
  opts.email = email;
  opts._id = email;
  opts.service = service;
  opts.fingerprint = fingerprint;
  var token = generate_random_code(7);
  opts.token = API.accounts.hash(token);
  var hash = Random.hexString(30);
  opts.hash = API.accounts.hash(hash);
  if (opts.url === undefined) opts.url = url;
  opts.url += "#" + hash;
  opts.timeout = (new Date()).valueOf() + ( (opts.timeout !== undefined ? opts.timeout : 30) * 60 * 1000 )
  loginCodes.insert(opts);

  var snd = {from: opts.from, to: email}
  if (opts.template) {
    snd.template = {filename:opts.template,service:opts.service};
    snd.vars = {
      useremail:email,
      loginurl:opts.url,
      logincode:token
    };
  } else {
    snd.subject = opts.subject;
    var re = new RegExp('\{\{LOGINCODE\}\}','g');
    snd.text = snd.text.replace(re,token);
    snd.html = snd.html.replace(re,token);
    var ure = new RegExp('\{\{LOGINURL\}\}','g');
    snd.text = snd.text.replace(ure,opts.url);
    snd.html = snd.html.replace(ure,opts.url);
  }
  var sent;
  if (send === undefined) send = true;
  if (send) {
    try { // try / catch on this lets things continue if say on dev the email is disabled
      snd.service = service;
      sent = API.mail.send(snd);
    } catch(err) {}
    var future = new Future(); // a delay here helps stop spamming of the login mechanisms
    setTimeout(function() { future.return(); }, 333);
    future.wait();
    return { mid: (sent && sent.data && sent.data.id ? sent.data.id : undefined) };
  } else {
    return {opts:opts,send:snd,token:token};
  }
}

API.accounts.login = function(email,token,hash,fingerprint,request) {
  loginCodes.remove('timeout.exact:"<' + (new Date()).valueOf() + '"'); // remove old logincodes
  var future = new Future(); // a delay here helps stop spamming of the login mechanisms
  setTimeout(function() { future.return(); }, 333);
  future.wait();
  var loginCode = hash ? loginCodes.find({hash:API.accounts.hash(hash)}) : loginCodes.find({email:email,token:API.accounts.hash(token)}); // could restrict to same fingerprint device if desired
  if (loginCode) {
    if (email === undefined) email = loginCode.email;
    loginCodes.remove({email:email}); // login only gets one chance
    var user = API.accounts.retrieve(email);
    if (!user) {
      user = API.accounts.create(email,fingerprint);
    } else if (fingerprint) {
      API.accounts.fingerprint(user,fingerprint);
    }
    if (!API.accounts.auth(loginCode.service+'.user',user)) API.accounts.addrole(user._id,loginCode.service,'user');
    if (request && API.settings.log.root && user.roles && user.roles.__global_roles__ && user.roles.__global_roles__.indexOf('root') !== -1) {
      var sb = 'root user login from ' + request.headers['x-real-ip'];
      API.log({msg:sb,notify:{subject:sb, text: 'root user logged in\n\n' + loginCode.url + '\n\n' + request.headers['x-real-ip'] + '\n\n' + request.headers['x-forwarded-for'] + '\n\n'}});
    }
    var resume = Random.hexString(30);
    var ts = Date.now();
    Users.update(user._id, {'security.resume':{token:resume,timestamp:ts}});
    return {
      apikey: user.api.keys[0].key,
      account: {
        email:email,
        _id:user._id,
        username:(user.username ? user.username : user.emails[0].address),
        profile:user.profile,
        roles:user.roles,
        serviceProfile:(user.service && user.service[loginCode.service] ? user.service[loginCode.service].profile : {})
      },
      settings: {
        timestamp:ts,
        resume: resume,
        path:'/',
        domain: loginCode.domain,
        expires: (API.settings.cookie.expires !== undefined ? API.settings.cookie.expires : 60),
        httponly: (API.settings.cookie.httponly !== undefined ? API.settings.cookie.httponly : false),
        secure: loginCode.secure !== undefined ? loginCode.secure : API.settings.cookie.secure
      }
    }
  } else {
    return {statusCode: 401, body: {status: 'error', data:'401 unauthorized'}}
  }
}

API.accounts.logout = function(val) {
  // may want an option to logout of all sessions...
  var user = API.accounts.retrieve(val);
  if (user) {
    Users.update(user._id, {'security.resume':{}});
    return true;
  } else {
    return {statusCode: 401, body: {status: 'error', data:'401 unauthorized'}}
  }
}

API.accounts.create = function(email,fingerprint) {
  if (JSON.stringify(email).indexOf('<script') !== -1 || email.indexOf('@') === -1) return false; // naughty catcher
  var password = Random.hexString(30);
  var apikey = Random.hexString(30);
  var u = {
    email:email,
    password:password,
    profile: {}, // profile data, all of which can be changed by the user
    devices: {}, // user devices associated by device fingerprint
    security: {},
    service: {}, // services identified by service name, which can be changed by those in control of the service
    api: { keys: [ { key: apikey, hashedToken: API.accounts.hash(apikey), name: 'default' } ] },
    emails: [
      {
        address: email,
        verified: true
      }
    ]
  };
  if (fingerprint) u.security.fingerprint = fingerprint;
  if ( Users.count() === 0 ) u.roles = {__global_roles__: ['root']};
  var uacc = Users.insert(u);
  API.log("Created userId = " + uacc._id);
  // create a group for this user, that they own?
  return {_id:uacc._id,password:password,apikey:apikey};
}

API.accounts.retrieve = function(val) {
  // finds and returns the full user account - NOT what should be returned to a user
  return Users.find('_id.exact:"' + val + '" OR username.exact:"' + val + '" OR emails.address.exact:"' + val + '" OR api.keys.key.exact:"' + val + '"');
}

API.accounts.details = function(uid,user) {
  // controls what should be returned about a user account based on the permission of the account asking
  // this is for use via API access - any code with access to this lib on the server could just call accounts directly to get everything anyway
  var uacc = user._id === uid ? user : API.accounts.retrieve(uid);
  var ret = {};
  if ( API.accounts.auth('root', user) ) {
    // any administrative account that is allowed full access to the user account can get it here
    ret = uacc;
  } else if (user._id === uacc._id || API.accounts.auth(uacc._id + '.read', user) ) {
    // this is the user requesting their own account - they do not get everything
    // a user should also have a group associated to their ID, and anyone with read on that group can get this data too
    ret._id = uacc._id;
    ret.profile = uacc.profile;
    ret.username = uacc.username;
    ret.emails = uacc.emails;
    ret.security = uacc.security; // this is security settings and info
    ret.api = uacc.api;
    ret.roles = uacc.roles;
    ret.status = uacc.status;
    if (uacc.service) {
      ret.service = {};
      for ( var s in uacc.service ) {
        if ( uacc.service[s].profile ) ret.service[s] = {profile: uacc.service[s].profile}
      }
    }
  } else if (uacc.service) {
    for ( var r in uacc.service ) {
      if ( API.accounts.auth(r + '.service', user) ) {
        ret._id = uacc._id;
        ret.profile = uacc.profile;
        ret.username = uacc.username;
        ret.emails = uacc.emails;
        ret.roles = uacc.roles; // should roles on other services be private?
        ret.status = uacc.status;
        ret.service = {}
        ret.service[r] = uacc.service[r];
        return ret;
      }
    }
  }
  return ret;
}

API.accounts.update = function(uid,user,keys,replace) {
  if (JSON.stringify(keys).indexOf('<script') !== -1) return false; // naughty catcher
  // account update does NOT handle emails, security, api, or roles
  var uacc = user._id === uid ? user : API.accounts.retrieve(uid);
  var allowed = {};
  if ( user._id === uacc._id || API.accounts.auth(uacc._id + '.edit', user) || API.accounts.auth('root', user) ) {
    // this is the user requesting their own account, or anyone with edit access on the group matching the user account ID
    // users can also edit the profile settings in a service they are a member of, if that service defined a profile for its users
    if (keys.username) allowed.username = keys.username
    if ( replace ) {
      if ( keys.profile ) allowed.profile = keys.profile;
      if ( keys.service ) {
        for ( var k in keys.service ) {
          if ( keys.service[k].profile ) allowed['service.'+k+'.profile'] = keys.service[k].profile
        }
      }
    } else {
      if ( keys.profile ) {
        for ( var kp in keys.profile ) allowed['profile.'+kp] = keys.profile[kp];
      }
      if ( keys.service ) {
        for ( var ks in keys.service ) {
          if ( keys.service[ks].profile ) {
            for ( var kk in keys.service[ks].profile ) allowed['service.'+ks+'.profile.'+kk] = keys.service[ks].profile[kk];
          }
        }
      }
    }
    if ( API.accounts.auth('root', user) ) {
      // the root user could also set a bunch of other things perhaps
    }
    Users.update(uid, allowed);
    return true;
  } else if ( uacc.service ) {
    for ( var r in uacc.service ) {
      if ( API.accounts.auth(r + '.service', user) && keys.service && keys.service[r] ) {
        // can edit this service section of the user account
        if (replace) {
          allowed['service.'+r] = keys.service[r];        
        } else {
          allowed['service.'+r] = {}
          // TODO this will not loop down levels at all - so could overwrite stuff in an object, for example
          for ( var kr in keys.service[r] ) allowed['service.'+r+'.'+kr] = keys.service[r][kr];
        }
        Users.update(uid, allowed);
        return true;
      }
    }
  }
  return false;
}

API.accounts.delete = function(uid,user,service) {
  // does delete actually delete, or just set as disabled?
  // service accounts should never delete, should just remove service section and groups/roles
  if ( API.accounts.auth('root',user) ) {
    API.log('Permanently deleting user ' + uid);
    Users.remove(uid);
    return true;
  } else {
    return false;
  }
}

API.accounts.auth = function(grl,user,cascade) {
  if (typeof grl === 'string') grl = [grl];
  for ( var g in grl ) {
    var gr = grl[g];
    if ( gr.split('.')[0] === user._id ) return 'root'; // any user is effectively root on their own group - which matches their user ID
    if ( !user.roles ) return false; // if no roles can't have any auth, except on own group (above)
    // override if user has global root always return true
    if ( user.roles.__global_roles__ && user.roles.__global_roles__.indexOf('root') !== -1 ) {
      API.log('user ' + user._id + ' has role root');
      return 'root';
    }
    // otherwise get group and role from gr or assume global role
    var role, grp;
    var rp = gr.split('.');
    if ( rp.length === 1 ) {
      grp = '__global_roles__';
      role = rp[0];
    } else {
      grp = rp[0];
      role = rp[1];
    }
    // check if user has group role specified
    if ( user.roles[grp] && user.roles[grp].indexOf(role) !== -1 ) {
      API.log('user ' + user._id + ' has role ' + gr);
      return role;
    }
    // or else check for higher authority in cascading roles for group
    // TODO ALLOW CASCADE ON GLOBAL OR NOT?
    // cascading roles, most senior on left, allowing access to all those to the right
    var cascading = ['root','service','super','owner','admin','auth','publish','edit','read','user','info','public'];
    if ( cascade === undefined ) cascade = true;
    if ( cascade ) {
      var ri = cascading.indexOf(role);
      if ( ri !== -1 ) {
        var cascs = cascading.splice(0,ri);
        for ( var r in cascs) {
          var rl = cascs[r];
          if ( user.roles[grp] && user.roles[grp].indexOf(rl) !== -1 ) {
            API.log('user ' + user._id + ' has cascaded role ' + grp + '.' + rl + ' overriding ' + gr);
            return rl;
          }
        }
      }
    }
    // otherwise user fails role check
    API.log('user ' + user._id + ' does not have role ' + gr);
  }
  return false;
}

API.accounts.addrole = function(uid,group,role,uacc) {
  if (uacc === undefined) uacc = API.accounts.retrieve(uid);
  // TODO if using groups, and if user should only get a role on an existing group, need to check group existence first...
  if (!uacc.roles) uacc.roles = {};
  if (!uacc.roles[group]) uacc.roles[group] = [];
  if (uacc.roles[group].indexOf(role) === -1) uacc.roles[group].push(role);
  var set = {};
  set['roles.'+group] = uacc.roles[group];
  if ( API.settings.service[group] ) {
    if (uacc.service === undefined) {
      set.service = {};
      set.service[group] = {profile:{}};
    } else if (uacc.service[group] === undefined) {
      set['service.'+group] = {profile:{}};
    }
  }
  Users.update(uacc._id, set);
  return {status: 'success'};
}

API.accounts.removerole = function(uid,group,role,uacc) {
  if (uacc === undefined) uacc = API.accounts.retrieve(uid);
  if (uacc.roles) {
    if (uacc.roles[group]) {
      var pos = uacc.roles[group].indexOf(role);
      if (pos !== -1) {
        uacc.roles[group].splice(pos,1);
        var set = {};
        set['roles.'+group] = uacc.roles[group];
        Users.update(uacc._id, set);
      }
    }
  }
  // TODO remove related service data?
  return {status: 'success'};
}

API.accounts.hash = function(token) {
  var hash = crypto.createHash('sha256');
  hash.update(token);
  return hash.digest('base64');
}



API.accounts.test = function() {
  var temail = 'a_test_account@noddy.com';
  var result = {passed:true,failed:[]};

  result.create = API.accounts.create(temail);
  if (typeof result.create !== 'object' || result.create._id === undefined) { result.passed = false; result.failed.push(1); }
  
  var future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();

  result.retrieved = API.accounts.retrieve(temail);
  if (result.retrieved._id !== result.create._id) { result.passed = false; result.failed.push(2); }
  
  result.addrole = API.accounts.addrole(result.retrieved._id,'testgroup','testrole');
  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.addedrole = API.accounts.retrieve(result.retrieved._id);
  if (!result.addedrole.roles || !result.addedrole.roles.testgroup || result.addedrole.roles.testgroup.indexOf('testrole') === 01) { result.passed = false; result.failed.push(3); }
  
  result.authorised = API.accounts.auth('testgroup.testrole',result.retrieved);
  if (result.authorised === false) { result.passed = false; result.failed.push(4); }

  result.removerole = API.accounts.removerole(result.retrieved._id,'testgroup','testrole');
  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.deauthorised = API.accounts.auth('testgroup.testrole',API.accounts.retrieve(result.retrieved._id));
  if (result.deauthorised !== false) { result.passed = false; result.failed.push(5); }
  
  result.token = API.accounts.token(temail,'https://testurl.com',undefined,undefined,false);
  if (!result.token || !result.token.opts || result.token.opts.email !== temail || !result.token.opts.token || result.token.opts.hash) { result.passed = false; result.failed.push(6); }

  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.logincode = loginCodes.find(temail);
  if (!result.logincode || result.logincode.token !== API.accounts.hash(result.token.token)) { result.passed = false; result.failed.push(7); }
  
  result.login = API.accounts.login(temail,result.token.token);
  if (!result.login || !result.login.account || result.login.account.email !== temail) { result.passed = false; result.failed.push(8); }

  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  result.logincodeRemoved = loginCodes.find(temail);
  if (result.logincodeRemoved !== false) { result.passed = false; result.failed.push(9); }
  
  var u = API.accounts.retrieve(temail);
  result.loggedin = u.security && u.security.resume && result.login && result.login.settings && u.security.resume.token && u.security.resume.token === result.login.settings.resume;
  if (result.loggedin !== true) { result.passed = false; result.failed.push(10); }
  
  result.logout = API.accounts.logout(temail);
  if (result.logout !== true) { result.passed = false; result.failed.push(11); }
  
  future = new Future();
  setTimeout(function() { future.return(); }, 999);
  future.wait();
  var u2 = API.accounts.retrieve(temail);
  result.logoutVerified = u2 && u2.security && JSON.stringify(u2.security.resume) === '{}';
  if (result.logoutVerified !== true) { result.passed = false; result.failed.push(12); }
  
  // API.accounts.delete is not checked yet, so far it can only be done by a root user and have not decided whether to actually fully remove 
  // accounts or just mark them as deleted
  
  //if (u2._id) Users.remove(u2._id);
  
  return result;
}




