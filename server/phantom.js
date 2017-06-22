
import phantom from 'phantom';
import fs from 'fs';

API.addRoute('phantom', {
  get: {
    action: function() {
      return {status:'success',data:'use phantom in various ways to render a page - for now, just get a rendered page back at phantom/get'}
    }
  }  
});

API.addRoute('phantom/get', {
  get: {
    action: function() {
      var format = this.queryParams.format ? this.queryParams.format : 'plain';
      return {
        statusCode: 200,
        headers: {
          'Content-Type': 'text/' + format
        },
        body: API.phantom.get(this.queryParams.url,this.queryParams.delay)
      };
    }
  }
});

API.phantom = {};

// return the content of the page at the redirected URL, after js has run
var _phantom = function(url,delay,callback) {
  if (url.indexOf('http') === -1) url = 'http://' + url;
  if (delay === undefined) delay = 5000;
  var phi,sp;
  API.log('starting phantom retrieval of ' + url);
  var ppath = '/usr/bin/phantomjs';
  var redirector;
  if (!fs.existsSync(ppath)) ppath = '/usr/local/bin/phantomjs';
  phantom.create(['--ignore-ssl-errors=yes','--load-images=no','--cookies-file=./cookies.txt'])
    .then(function(ph) {
      phi = ph;
      API.log('creating page');
      return phi.createPage();
    })
    .then(function(page) {
      sp = page;
      sp.setting('resourceTimeout',3000);
      sp.setting('loadImages',false);
      sp.setting('userAgent','Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36');
      API.log('retrieving page');
      sp.onResourceReceived = function(resource) {
        if (url == resource.url && resource.redirectURL) {
          redirector = resource.redirectURL;
        }
      }
      return sp.open(url);
    })
    .then(function(status) {
      if (redirector) {
        API.log('redirecting to ' + redirector);
        sp.close();
        phi.exit();
        _phantom(redirector,delay,callback);
      } else {
        API.log('retrieving content');
        var Future = Npm.require('fibers/future');
        var future = new Future();
        setTimeout(function() { future.return(); }, delay);
        future.wait();
        return sp.property('content');
      }
    })
    .then(function(content) {
      API.log(content.length);
      if (content.length < 200 && delay < 10000 ) {
        delay += 5000;
        sp.close();
        phi.exit();
        redirector = undefined;
        API.log('trying again with delay ' + delay);
        _phantom(url,delay,callback);
      } else {
        API.log('got content');
        sp.close();
        phi.exit();
        redirector = undefined;
        return callback(null,content);
      }
    })
    .catch(function(error) {
      API.log({msg:'phantom errored',error:error});
      sp.close();
      phi.exit();
      redirector = undefined;
      return callback(null,'');
    });
    
}
API.phantom.get = Meteor.wrapAsync(_phantom);



API.phantom.test = function() {
  var result = {passed:true,failed:[]}
  
  var pg = API.phantom.get('https://cottagelabs.com');
  if (pg.toLowerCase().indexOf('cottage labs') === -1) { result.passed = false; result.failed.push(1); }
  
  return result;
}





