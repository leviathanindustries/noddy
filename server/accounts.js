
//Users = new API.collection({type:"users",history:true});
loginCodes = new API.collection("logincodes");

API.addRoute('accounts', {
  get: {
    authRequired:true,
    action: function() {
      if ( API.accounts.auth('root', this.user) ) {
        return Users.search(this.bodyParams,this.queryParams);
      } else {
        return {status: 'success', data: Users.count() };
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
API.addRoute('accounts/token', {
  get: {
    action: function() {
      return API.accounts.token(this.queryParams.email,this.queryParams.location,this.queryParams.fingerprint);
    }
  },
  post: {
    action: function() {
      return API.accounts.token(this.request.body.email,this.request.body.location,this.request.body.fingerprint);
    }
  }
});
API.addRoute('accounts/login', {
  post: {
    action: function() {
      return API.accounts.login(this.request.body.email,this.request.body.location,this.request.body.token,this.request.body.hash,this.request.body.fingerprint,this.request.body.resume,this.request.body.timestamp,this.request)
    }
  }
});
API.addRoute('accounts/logout', {
  post: {
    action: function() {
      return API.accounts.logout(this.request.body.email,this.request.body.resume,this.request.body.timestamp,this.request.body.location)
    }
  }
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

API.addRoute('accounts/:id/roles/:grouprole', {
  post: {
    authRequired: true,
    action: function() {
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

function template(str,opts) {
  for ( var k in opts ) {
    var re = new RegExp('\{\{' + k.toUpperCase() + '\}\}','g');
    str = str.replace(re,opts[k]);
  }
  return str;
}

API.accounts = {};

API.accounts.service = function(location) {
  // update this to accept settings object too, which should update the service settings
  // at which point perhaps service settings should be on mongo rather than in a text file
  // return the options for a given location
  location = location.trim('/');
  if ( login_services[location] === undefined) {
    API.log('BAD TOKEN ATTEMPT FROM ' + location);
    return false;
    // should not be logging in from a page we don't set as being able to provide login functionality. 
    // Say nothing, no explanation. Worth sending a sysadmin email?
  } else {
    var opts = {};
    for ( var o in login_services.default ) opts[o] = login_services.default[o];
    for ( var k in login_services[location] ) opts[k] = login_services[location][k];
    return opts;
  }
}

// receive a device fingerprint and perhaps some settings (e.g. to make it a registered / named device)
API.accounts.fingerprint = function(uid,fingerprint) {
  // TODO fingerprint should go in devices area of account, with mutliple fingerprints and useful info possible
  // for now just sets the fingerprint
  var user = API.accounts.retrieve(uid);
  var set = {}
  if (user.security) {
    set['security.fingerprint'] = fingerprint;    
  } else {
    set.security = {fingerprint:fingerprint}
  }
  Users.update(user._id, {$set: set});
}

// require email string, optional fingerprint string
// expect service object, containing a service key pointing to service object data
// which can contain a role - or get role from service options now?
API.accounts.register = function(opts) {
  if (JSON.stringify(opts).indexOf('<script') !== -1) return false; // naughty catcher
  if (opts.email === undefined) return false;
  // fingerprint cannot be mandatory because it can not be used easily on APIs
  var user = API.accounts.retrieve(opts.email);
  if ( !user ) {
    var set = { email: opts.email };
    if (opts.fingerprint) {
      //set.devices = {};
      //set.devices[opts.fingerprint] = {};
      set.security = {fingerprint:opts.fingerprint};
      // TODO should have a devices area with mutliple fingerprints and device info possible
    }
    set.service = {};
    if ( opts.service ) set.service[opts.service.service] = {profile:{}}; // TODO this should save service info if necessary
    var creds = API.accounts.create( set );
    user = API.accounts.retrieve(creds._id);
  } else if (opts.fingerprint) {
    API.accounts.fingerprint(user._id,opts.fingerprint);
  }
  if ( opts.service ) {
    if ( user.service === undefined ) user.service = {};
    if ( user.service[opts.service.service] === undefined ) user.service[opts.service.service] = {profile:{}};
    // TODO are there any values in service settings that should be saved into the service object on account creation?
    Users.update(user._id, {$set: {'service':user.service}});
    if (opts.service.role && ( !user.roles || !user.roles[opts.service.service] || user.roles[opts.service.service].indexOf(opts.service.role) === -1 ) ) {
      API.accounts.addrole(user._id, opts.service.service, opts.service.role);
    }
  }
}

API.accounts.token = function(email,loc,fingerprint) {
  // check that loc is in the allowed signin locations list (can be faked, but worthwhile)
  // TODO need a check to see if the location they want to sign in to is one that allows registrations without confirmation
  // if it does not, and if the user account is not already known and with access to the requested service name, then the token should be denied
  // if this does happen, then an account request for the specified service should probably be generated somehow
  var opts = API.accounts.service(loc);
  if (!opts) return {};
  API.log(email + ' token request via API');
  opts.logincode = generate_random_code(Meteor.settings.LOGIN_CODE_LENGTH);
  var loginhash = generate_random_code();
  if (opts.loginurl === undefined) opts.loginurl = loc;
  opts.loginurl += "#" + loginhash;
  var until = (new Date()).valueOf() + (opts.timeout * 60 * 1000);
  opts.timeout = opts.timeout >= 60 ? (opts.timeout/60) + ' hour(s)' : opts.timeout + ' minute(s)';
  var user = API.accounts.retrieve(email);
  opts.action = user && API.accounts.auth(opts.service+'.'+opts.role,user) ? "login" : "registration";
  API.log(opts);

  if (opts.action === "registration" && !opts.registration) {
    // TODO could register a registration request somehow, and then email whoever should be in charge of those for this service
    // should be a group role request, which should trigger a request email which should have an allow/deny link
    return { known:(user !== undefined), registration:opts.registration };
  } else {
    var known = false;
    if (user) {
      known = true;
      // check the user has a user role in this service, otherwise give it to them
      if (opts.action === "registration" && !API.accounts.auth(opts.service+'.'+opts.role,user)) {
        API.accounts.addrole(user._id,opts.service,opts.role);
      }
      if (fingerprint) API.accounts.fingerprint(user._id,fingerprint);
    } else {
      if (!opts.role) opts.role = 'user';
      user = API.accounts.register({email:email,service:opts,fingerprint:fingerprint});
    }
    
    var up = {email:email,code:opts.logincode,hash:loginhash,timeout:until,service:opts.service};
    if ( fingerprint ) up.fp = fingerprint;
    loginCodes.upsert({email:email},up);
    
    var snd = {from: opts.from, to: email}
    if (opts.template) {
      snd.template = {filename:opts.template,service:opts.service};
      snd.vars = {
        useremail:email,
        loginurl:opts.loginurl,
        logincode:opts.logincode
      };
    } else {
      snd.subject = template(opts.subject,opts);
      snd.text = template(opts.text,opts);
      snd.html = template(opts.html,opts);
    }
    var sent;
    try {
      // try / catch on this lets things continue if say on dev the email is disabled
      snd.post = true;
      if (snd.post && Meteor.settings[opts.service] && Meteor.settings[opts.service].mail_service && Meteor.settings[opts.service].mail_apikey) {
        snd.mail_service = Meteor.settings[opts.service].mail_service;
        snd.mail_apikey = Meteor.settings[opts.service].mail_apikey;
      } else if (snd.post && Meteor.settings.MAIL_SERVICE && Meteor.settings.MAIL_APIKEY) {
        snd.mail_service = Meteor.settings.MAIL_SERVICE;
        snd.mail_apikey = Meteor.settings.MAIL_APIKEY;
      } else {
        snd.post = false;
      }
      sent = API.mail.send(snd,Meteor.settings.service_mail_urls[opts.service]);
      API.log(sent)
    } catch(err) {}

    var future = new Future(); // a delay here helps stop spamming of the login mechanisms
    setTimeout(function() { future.return(); }, 333);
    future.wait();
    var mid = sent && sent.data && sent.data.id ? sent.data.id : undefined;
    return { known:known, mid: mid };
  }
}

API.accounts.login = function(email,loc,token,hash,fingerprint,resume,timestamp,request) {
  var opts = API.accounts.service(loc);
  if (!opts) return {};
  // given an email address or token or hash, plus a fingerprint, login the user
  API.log("API login for email address: " + email + " at location " + loc + " - with token: " + token + " or hash: " + hash + " or fingerprint: " + fingerprint + " or resume " + resume + " and timestamp " + timestamp);
  loginCodes.remove({ timeout: { $lt: (new Date()).valueOf() } }); // remove old logincodes
  var loginCode;
  var user;
  if (token !== undefined && email !== undefined) loginCode = loginCodes.findOne({email:email,code:token});
  if (!loginCode && fingerprint !== undefined && email !== undefined) loginCode = loginCodes.findOne( { $and: [ { email:email, fp:fingerprint } ] } );
  if (!loginCode && hash !== undefined && fingerprint !== undefined) loginCode = loginCodes.findOne( { $and: [ { hash:hash, fp:fingerprint } ] } );
  if (!loginCode && hash !== undefined) loginCode = loginCodes.findOne({hash:hash});
  if (!loginCode && email !== undefined && resume !== undefined && timestamp !== undefined) {
    API.log('searching for login for user email via timestamped resume token');
    user = Users.findOne({'emails.address':email,'security.resume.token':resume,'security.resume.timestamp':timestamp});
  }
  // TODO could also check by email and fingerprint if both present - but fingerprint on its own is far too weak
  // any site can generate the fingerprint and then guess the email address
  var future = new Future(); // a delay here helps stop spamming of the login mechanisms
  setTimeout(function() { future.return(); }, 333);
  future.wait();
  if (loginCode || user) {
    if (email === undefined && loginCode) email = loginCode.email;
    if (fingerprint === undefined && loginCode && loginCode.fingerprint) fingerprint = loginCode.fingerprint;
    if (loginCode) loginCodes.remove({email:email}); // login only gets one chance
    if (!user) {
      API.accounts.register({email:email,fingerprint:fingerprint,service:{service:loginCode.service}});
      user = API.accounts.retrieve(email);
    }
    if (Meteor.settings.ROOT_LOGIN_WARN && user.roles && user.roles.__global_roles__ && user.roles.__global_roles__.indexOf('root') !== -1) {
      API.log('root user logged in ' + user._id);
      if (!Meteor.settings.dev) {
        var from = 'alert@cottagelabs.com';
        var xf = request.headers['x-forwarded-for'];
        var xr = request.headers['x-real-ip'];
        var subject = 'root account login ' + xr;
        API.mail.send({from: from, to:'mark@cottagelabs.com',subject:subject,text:'root user logged in\n\n' + user._id + '\n\n' + loc + '\n\n' + xr + '\n\n' + xf + '\n\n'});
      }
    }
    // generating new resume tokens every time was always going to push quite a load to the db, 
    // but it also seems impossible to reliably implement, due to what appears to be browser prefetching
    // so for now only create new ones on first login attempt, otherwise just pass the same ones back
    // can implement a resume timeout length here too, if timestamp is too old, throw it away
    var newresume = resume ? resume : generate_random_code();
    var newtimestamp = timestamp ? timestamp : Date.now();
    if (newresume !== resume) Users.update(user._id, {$set: {'security.resume':{token:newresume,timestamp:newtimestamp}}});
    var service = {};
    if ( user.service[opts.service] ) {
      service[opts.service] = {};
      if (user.service[opts.service].profile) service[opts.service].profile = user.service[opts.service].profile;
      // which service info can be returned to the user account?
      // TODO should probably have public and private sections, for now has profile section, 
      // which can definitely be shared whereas nothing else cannot. Maybe that will do.      
    }
    //API.log('accounts login returning successfully');
    var username = user.username ? user.username : user.emails[0].address;
    return {
      status:'success', 
      data: {
        apikey: user.api.keys[0].key,
        account: {
          _id:user._id,
          username:user.username,
          profile:user.profile,
          roles:user.roles,
          service:service
        },
        cookie: {
          email:email,
          userId:user._id,
          username:username,
          roles:user.roles,
          timestamp:newtimestamp,
          domain:opts.domain,
          url:loc,
          domain: opts.domain,
          resume: newresume
        },
        settings: {
          path:'/',
          domain: opts.domain,
          expires: Meteor.settings.public.loginState.maxage,
          httponly: Meteor.settings.public.loginState.HTTPONLY_COOKIES,
          secure: opts.secure !== undefined ? opts.secure : Meteor.settings.public.loginState.SECURE_COOKIES
        }
      }
    }
  } else {
    //API.log('returning accounts login false');
    return {statusCode: 401, body: {status: 'error', data:'401 unauthorized'}}
  }
}

API.accounts.logout = function(email,resume,timestamp,loc) {
  if ( login_services[loc] === undefined) {
    API.log('BAD LOGOUT ATTEMPT FROM ' + loc);
    return {}; // should not be logging in from a page we don't set as being able to provide login functionality. Say nothing, no explanation. Worth sending a sysadmin email?
  }
  // may want an option to logout of all sessions...
  if (email !== undefined && resume !== undefined && timestamp !== undefined) {
    var user = Users.findOne({'emails.address':email,'security.resume.token':resume,'security.resume.timestamp':timestamp});
    if (user) {
      var opts = {};
      for ( var o in login_services.default ) opts[o] = login_services.default[o];
      for ( var k in login_services[loc] ) opts[k] = login_services[loc][k];
      Users.update(user._id, {$set: {'security.resume':{}}}); // TODO what else could be thrown away here? resume tokens?
      return {status:'success',data:{domain:opts.domain}} // so far this is all that is needed to clear the user login cookie
    } else {
      return {statusCode: 401, body: {status: 'error', data:'401 unauthorized'}}
    }
  } else {
    return {statusCode: 401, body: {status: 'error', data:'401 unauthorized'}}
  }
}


API.accounts.create = function(data) {
  if (JSON.stringify(data).indexOf('<script') !== -1) return false; // naughty catcher
  if (data.email === undefined) throw new Error('At least email field required');
  if (data.password === undefined) data.password = Random.hexString(30);
  var userId = Accounts.createUser({email:data.email,password:data.password});
  API.log("CREATED userId = " + userId);
  // create a group for this user, that they own?
  if (data.apikey === undefined) data.apikey = Random.hexString(30);
  // need checks for profile data, service data, and other special fields in the incoming data
  var sets = {
    profile: data.profile ? data.profile : {}, // profile data, all of which can be changed by the user
    devices: data.devices ? data.devices : {}, // user devices associated by device fingerprint
    security: data.security ? data.security : {}, // user devices associated by device fingerprint
    service: {}, // services identified by service name, which can be changed by those in control of the service
    api: {
      keys: [
        {
          key: data.apikey, 
          hashedToken: API.accounts.hash(data.apikey), 
          name: 'default'
        }
      ] 
    }, 
    'emails.0.verified': true
  }
  if (data.username) sets.username = data.username;
  if (data.service) {
    for ( var s in data.service ) {
      if ( data.service[s].role ) {
        API.accounts.addrole(userId, s, data.service[s].role);
        delete data.service[s].role;
      }
      sets.service[s] = data.service[s];
    }
  }
  Users.update(userId, {$set: sets});
  if ( Users.count() === 1 ) API.accounts.addrole(userId, '__global_roles__', 'root');
  return {_id:userId,password:data.password,apikey:data.apikey};
}

API.accounts.retrieve = function(uid) {
  // finds and returns the full user account - NOT what should be returned to a user
  var u = Users.findOne(uid);
  if (!u) u = Users.findOne({username:uid});
  if (!u) u = Users.findOne({'emails.address':uid});
  if (!u) u = Users.findOne({'api.keys.key':uid});
  return u;
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
    Users.update(uid, {$set: allowed});
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
        Users.update(uid, {$set: allowed});
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
    API.log('TODO accounts API should delete user ' + uid);
    //Users.remove(uid);
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
  Users.update(uacc._id,{$set:set});
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
        Users.update(uacc._id,{$set:set});
      }
    }
  }
  // TODO remove related service data?
  return {status: 'success'};
}


API.accounts.hash = function(token) {
  return token; // TODO need to be a function that hashes what is provided, to be matched against a stored hash
  // to replace Accounts._hashLoginToken
  // although so far only needed if /login and /logout routes are used in restivus.coffee, which so far they are not
}
