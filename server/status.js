
// an API status reporter

API.addRoute('status', {
  get: {
    action: function() {
      return API.status();
    }
  }
});

API.addRoute('status/check', {
  get: {
    //roleRequired: 'root',
    action: function() {
      return API.check();
    }
  }
});

API.addRoute('status/test', {
  get: {
    //roleRequired: 'root',
    action: function() {
      return API.test(this.queryParams.verbose);
    }
  }
});



API.status = function() {
  var ret = {
    up: {
      live:true,
      local:true,
      cluster:true,
      dev:true
    },
    accounts: {
      total: Users.count()//,
      //online: API.accounts.onlinecount()
    },
    cron: 'TODO'
  }
  try { HTTP.call('GET','https://api.cottagelabs.com'); } catch(err) { ret.up.live = false; }
  try { HTTP.call('GET','https://lapi.cottagelabs.com'); } catch(err) { ret.up.local = false; }
  try { HTTP.call('GET','https://dev.api.cottagelabs.com'); } catch(err) { ret.up.dev = false; }
  try { 
    HTTP.call('GET','https://capi.cottagelabs.com');
    if (API.settings.cluster && API.settings.cluster.machines) {
      var cm = 0;
      for ( var m in API.settings.cluster.machines) {
        try {
          HTTP.call('GET','http://' + API.settings.cluster.machines[m] + '/api');
          cm += 1;
        } catch(err) {}
      }
      if (cm !== 0) ret.up.cluster = cm;
    }
  } catch(err) { ret.up.cluster = false; }
  // TODO if cluster is up could read the mup file then try getting each cluster machine too, and counting them
  try { ret.job = API.job.status(); } catch(err) { ret.job = false; }
  try { ret.limit = API.limit.status(); } catch(err) { ret.limit = false; }
  try { ret.index = API.es.status(); } catch(err) { ret.index = false; }
  try { ret.lantern = API.service.lantern.status(); } catch(err) { ret.lantern = false; }
  try { ret.openaccessbutton = API.service.oab.status(); } catch(err) { ret.openaccessbutton = false; }
  return ret;
};



API.test = function(verbose,trigger) {
  var tests = {passed:true,trigger:trigger}; // trigger can just be some useful string say to indicate which cron job triggered a test
  // could add an elasticsearch test, but a collection test won't succeed unless ES succeeds anyway
  /*
  if (API.collection && API.collection.test) {
    tests.collection = API.collection.test();
    if (tests.collection.passed && !verbose) tests.collection = {passed:true};
    tests.passed = tests.passed && tests.collection.passed;
  }
  if (API.mail && API.mail.test) {
    tests.mail = API.mail.test();
    if (tests.mail.passed && !verbose) tests.mail = {passed:true};
    tests.passed = tests.passed && tests.mail.passed;
  }
  if (API.accounts && API.accounts.test) {
    tests.accounts = API.accounts.test();
    if (tests.accounts.passed && !verbose) tests.accounts = {passed:true};
    tests.passed = tests.passed && tests.accounts.passed;
  }
  if (API.convert && API.convert.test) {
    tests.convert = API.convert.test();
    if (tests.convert.passed && !verbose) tests.convert = {passed:true};
    tests.passed = tests.passed && tests.convert.passed;
  }
  // add a job, limit, and phantom test?*/
  for ( var e in API ) {
    if (API[e].test) {
      tests[e] = API[e].test();
      if (tests[e].passed && !verbose) tests[e] = {passed:true};
      tests.passed = tests.passed && tests[e].passed;
    }    
  }
  tests.service = {};
  for ( var s in API.service ) {
    if (API.service[s].test) {
      tests.service[s] = API.service[s].test();
      if (tests.service[s].passed && !verbose) tests.service[s] = {passed:true};
      tests.passed = tests.passed && tests.service[s].passed;
    }
  }
  tests.use = {};
  for ( var u in API.use ) {
    if (API.use[u].test) {
      tests.use[u] = API.use[u].test();
      if (tests.use[u].passed && !verbose) tests.use[u] = {passed:true};
      tests.passed = tests.passed && tests.use[u].passed;
    }
  }
  var notify = tests.passed ? undefined : {msg:JSON.stringify(tests,undefined,2)};
  API.log({msg:'Completed testing',tests:tests,notify:notify});
  return tests;
}



API.check = function() {
  // for every use endpoint, send a request and check that the response looks like some stored known response
  // first check is, do we still get an answer back? and perhaps how long did it take?
  // check all params exist, look for new ones, look for different values, and give details of difference
  var check = {
    status: 'success,change,error',
    check:{
    }
  };
  // TODO some sort of overall analysis to determine what overall status should be
  // if overall status is not success, email sysadmin with details
  return check;
}

// could add a cron to run checks and tests every day and email a sysadmin


