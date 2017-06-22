
import request from 'request';
import { Converter } from 'csvtojson';
import json2csv from 'json2csv';
import html2txt from 'html-to-text';
import textract from 'textract';
import xml2js from 'xml2js';
import PDFParser from 'pdf2json';

// convert things to other things

API.addRoute('convert', {
  get: {
    action: function() {
      if ( this.queryParams.url || this.queryParams.content || this.queryParams.es ) {
        if (this.queryParams.fields) this.queryParams.fields = this.queryParams.fields.split(',');
        var to = 'text/plain';
        if (this.queryParams.to === 'csv') to = 'text/csv';
        if (this.queryParams.to === 'json' || this.queryParams.to === 'xml') to = 'application/' + this.queryParams.to;
        var out = API.convert.run(this.queryParams.url,this.queryParams.from,this.queryParams.to,this.queryParams.content,this.queryParams);
        try {
          if (out.statusCode === 401) return out; // an es query can cause a 401 unauth passback
        } catch(err) {}
        return {
          statusCode: 200,
          headers: {
            'Content-Type': to
          },
          body: out
        }
      } else {
        return {status: 'success', data: {info: 'Accepts URLs of content files and converts them. from csv to json,txt. from html to txt. from xml to txt, json. from pdf to txt. from file to txt. For json to csv a subset param can be provided, giving dot notation to the part of the json object that should be converted.'} };
      }
    }
  },
  post: {
    action: function() {
      if (this.queryParams.fields) this.queryParams.fields = this.queryParams.fields.split(',');
      var to = 'text/plain';
      if (this.queryParams.to === 'csv') to = 'text/csv';
      if (this.queryParams.to === 'json' || this.queryParams.to === 'xml') to = 'application/' + this.queryParams.to;
      return {
        statusCode: 200,
        headers: {
          'Content-Type': to
        },
        body: API.convert.run(undefined,this.queryParams.from,this.queryParams.to,this.request.body,this.queryParams)
      }
    }
  }
});

API.addRoute('convert/test', { get: { /*roleRequired: 'root',*/ action: function() { return API.convert.test(this.queryParams.fixtures); } } });



API.convert = {};

API.convert.run = function(url,from,to,content,opts) {
  if (from === undefined && opts.from) from = opts.from;
  if (to === undefined && opts.to) to = opts.to;
  var which, proc, output;
  if ( from === 'table' ) { // convert html table in web page
    if ( to.indexOf('json') !== -1 ) {
      output = API.convert.table2json(url,content,opts);
    } else if ( to.indexOf('csv') !== -1 ) {
      output = API.convert.table2csv(url,content,opts);      
    }
  } else if ( from === 'csv' ) {
    if ( to.indexOf('json') !== -1 ) {
      output = API.convert.csv2json(url,content,opts);
    } else if ( to.indexOf('txt') !== -1 ) {
      from = 'file';
    }
  } else if ( from === 'html' ) {
    if ( to.indexOf('txt') !== -1 ) {
      output = API.convert.html2txt(url,content);
    }
  } else if ( from === 'json' ) {
    if (opts.es) {
      // query local ES action with the given query, which will only work for users with the correct auth
      var user;
      if (opts.apikey) API.accounts.retrieve(opts.apikey);
      var uid = user ? user._id : undefined; // because could be querying a public ES endpoint
      var params = {};
      if (opts.es.indexOf('?') !== -1) {
        var prs = opts.es.split('?')[1];
        var parts = prs.split('&');
        for ( var p in parts ) {
          var kp = parts[p].split('=');
          params[kp[0]] = kp[1];
        }
      }
      opts.es = opts.es.split('?')[0];
      if (opts.es.substring(0,1) === '/') opts.es = opts.es.substring(1,opts.es.length-1);
      var rts = opts.es.split('/');
      content = API.es.action(uid,'GET',rts,params);
      if (content.statusCode === 401) return content;
      delete opts.es;
      delete opts.apikey;
      url = undefined;
    }
    if ( to.indexOf('csv') !== -1 ) {
      output = API.convert.json2csv(opts,url,content);
    } else if ( to.indexOf('txt') !== -1 ) {
      from = 'file';
    } else if ( to.indexOf('json') !== -1 ) {
      output = API.convert.json2json(opts,url,content);
    }
  } else if ( from === 'xml' ) {
    if ( to.indexOf('txt') !== -1 ) {
      output = API.convert.xml2txt(url,content);
    } else if ( to.indexOf('json') !== -1 ) {
      output = API.convert.xml2json(url,content);
    }
  } else if ( from === 'pdf' ) {
    if ( to.indexOf('txt') !== -1 ) {
      output = API.convert.pdf2txt(url,content,opts);
    } else if ( to.indexOf('json') !== -1 ) {
      output = API.convert.pdf2json(url,content,opts);
    }
  }
  if ( from === 'file' ) { // some of the above switch to this, so separate loop
    if ( to.indexOf('txt') !== -1 ) {
      output = API.convert.file2txt(url,content,opts);
    }
  }
  if ( output === undefined ) {
    return {status: 'error', data: 'conversion from ' + from + ' to ' + to + ' is not currently possible.'}
  } else {
    return output;
  }
}

var _csv2json = function(url,content,opts,callback) {
  var converter;
  if ( content === undefined ) {
    converter = new Converter({constructResult:false});
    var recs = [];
    converter.on("record_parsed", function (row) {
      recs.push(row);
    });
    request.get(url).pipe(converter);
    return recs; // this probably needs to be on end of data stream
  } else {
    converter = new Converter({});
    converter.fromString(content,function(err,result) {
      return callback(null,result);
    });
  }
}
API.convert.csv2json = Meteor.wrapAsync(_csv2json);

API.convert.table2json = function(url,content,opts) {
  if ( url !== undefined) {
    var res = HTTP.call('GET', url);
    content = res.content;
  }
  if ( opts.start ) content = content.split(opts.start)[1];
  if ( content.indexOf('<table') !== -1 ) {
    content = '<table' + content.split('<table')[1];
  } else if ( content.indexOf('<TABLE') !== -1 ) {
    content = '<TABLE' + content.split('<TABLE')[1];      
  }
  if ( opts.end ) content = content.split(opts.end)[0];
  if ( content.indexOf('</table') !== -1 ) {
    content = content.split('</table')[0] + '</table>';
  } else if ( content.indexOf('</TABLE') !== -1 ) {
    content = content.split('</TABLE')[1] + '</TABLE>';
  }
  content = content.replace(/\\n/gi,'');
  var ths = content.match(/<th.*?<\/th/gi);
  var headers = [];
  var results = [];
  for ( var h in ths ) {
    var str = ths[h].replace(/<th.*?>/i,'').replace(/<\/th.*?/i,'');
    str = str.replace(/<.*?>/gi,'').replace(/&nbsp;/gi,'');
    if (str.replace(/ /g,'').length === 0) str = 'UNKNOWN';
    headers.push(str);
  }
  var rows = content.match(/<tr.*?<\/tr/gi);
  for ( var r in rows ) {
    if ( rows[r].toLowerCase().indexOf('<th') === -1 ) {
      var result = {};
      var row = rows[r].replace(/<tr.*?>/i,'').replace(/<\/tr.*?/i,'');
      var vals = row.match(/<td.*?<\/td/gi);
      for ( var d = 0; d < vals.length; d++ ) {
        var keycounter = d;
        if ( vals[d].toLowerCase().indexOf('colspan') !== -1 ) {
          try {
            var count = parseInt(vals[d].toLowerCase().split('colspan')[1].split('>')[0].replace(/[^0-9]/,''));
            keycounter += (count-1);
          } catch(err) {}
        }
        var val = vals[d].replace(/<.*?>/gi,'').replace('</td','');
        if (headers.length > keycounter) {
          result[headers[keycounter]] = val;
        }
      }
      if (result.UNKNOWN !== undefined) delete result.UNKNOWN;
      results.push(result);
    }
  }
  return results;
}

API.convert.table2csv = function(url,content,opts) {
  var d = API.convert.table2json(url,content,opts);
  return API.convert.json2csv(undefined,undefined,d);
}

API.convert.html2txt = function(url,content) {
  // TODO should we use some server-side page rendering here? 
  // such as phantomjs, to get text content before rendering to text?
  if ( url !== undefined) {
    var res = HTTP.call('GET', url);
    content = res.content;
  }
  var text = html2txt.fromString(content, {wordwrap: 130});
  return text;
};

API.convert.file2txt = Meteor.wrapAsync(function(url, content, opts, callback) {
  // NOTE for this to work, see textract on npm - requires other things installed. May not be useful
  if (opts === undefined) opts = {};
  var from = opts.from !== undefined ? opts.from : 'application/msword';
  if (opts.from !== undefined) delete opts.from;
  
  if (url !== undefined) {
    var res = HTTP.call('GET',url,{npmRequestOptions:{encoding:null}});
    content = new Buffer(res.content);
  } else {
    content = new Buffer(content);
  }
  textract.fromBufferWithMime(from, content, opts, function( err, result ) {
    return callback(null,result);
  });
});

var _pdf2txt = function(url,content,callback) {
  var pdfParser = new PDFParser();
  pdfParser.on("pdfParser_dataReady", pdfData => {
    return callback(null,pdfParser.getRawTextContent());
  });
  if (url !== undefined) {
    var res = HTTP.call('GET',url);
    content = new Buffer(res.content);
  } else {
    content = new Buffer(content);
  }
  pdfParser.parseBuffer(content);
}
API.convert.pdf2txt = Meteor.wrapAsync(_pdf2txt);

var _pdf2json = function(url,content,callback) {
  var pdfParser = new PDFParser();
  pdfParser.on("pdfParser_dataReady", pdfData => {
    return callback(null,pdfData);
  });
  if (url !== undefined) {
    var res = HTTP.call('GET',url);
    content = new Buffer(res.content);
  } else {
    content = new Buffer(content);
  }
  pdfParser.parseBuffer(content);
}
API.convert.pdf2json = Meteor.wrapAsync(_pdf2json);

API.convert.xml2txt = function(url,content) {
  return API.convert.file2txt(url,content,{from:'application/xml'});
}

API.convert.xml2json = Meteor.wrapAsync(function(url, content, callback) {
  if ( url !== undefined ) {
    var res = HTTP.call('GET', url);
    content = res.content;
  }
  var parser = new xml2js.Parser();
  parser.parseString(content, function (err, result) {
    return callback(null,result);
  });
});

API.convert.json2csv = Meteor.wrapAsync(function(opts, url, content, callback) {
  if ( url !== undefined ) {
    var res = HTTP.call('GET', url);
    content = JSON.parse(res.content);
  }
  if (opts === undefined) opts = {};
  if (opts.subset) {
    var parts = opts.subset.split('.');
    delete opts.subset;
    for ( var p in parts ) {
      if (Array.isArray(content)) {
        var c = [];
        for ( var r in content ) c.push(content[r][parts[p]]);
        content = c;
      } else  {
        content = content[parts[p]];
      }
    }
  }
  for ( var l in content ) {
    for ( var k in content[l] ) {
      if ( Array.isArray(content[l][k]) ) {
        content[l][k] = content[l][k].join(',');
      }
    }
  }
  opts.data = content;
  json2csv(opts, function(err, result) {
    if (result) result = result.replace(/\\r\\n/g,'\r\n');
    return callback(null,result);
  });
});

API.convert.json2json = function(opts,url,content) {
  if ( url !== undefined ) {
    var res = HTTP.call('GET', url);
    content = JSON.parse(res.content);
  }
  if (opts.subset) {
    var parts = opts.subset.split('.');
    for ( var s in parts ) {
      content = content[parts[s]];
    }
  }
  if ( opts.fields ) {
    var recs = [];
    for ( var r in content ) {
      var rec = {};
      for ( var f in opts.fields ) {
        rec[opts.fields[f]] = content[r][opts.fields[f]];
      }
      recs.push(rec);
    }
    content = recs;
  }
  return content;
}



API.convert.test = function(fixtures) {
  /*if (fixtures === undefined && API.settings.fixtures && API.settings.fixtures.url) fixtures = API.settings.fixtures.url;
  if (fixtures === undefined) return {passed: false, failed: [], NOTE: 'fixtures.url MUST BE PROVIDED IN SETTINGS FOR THIS TEST TO RUN, and must point to a folder containing files called test in csv, html, pdf, xml and json format'}

  var result = {passed:true,failed:[]};
  
  result.csv2json = API.convert.run(fixtures + 'test.csv','csv','json');
  
  result.table2json = API.convert.run(fixtures + 'test.html','table','json');
  
  result.html2txt = API.convert.run(fixtures + 'test.html','html','txt');
  
  //result.file2txt = API.convert.run(fixtures + 'test.doc','file','txt');

  result.pdf2txt = API.convert.run(fixtures + 'test.doc','pdf','txt');

  result.xml2txt = API.convert.run(fixtures + 'test.xml','xml','txt');
  
  result.xml2json = API.convert.run(fixtures + 'test.xml','xml','json');
  
  result.json2csv = API.convert.run(fixtures + 'test.json','json','csv');
  
  result.json2json = API.convert.run(fixtures + 'test.json','json','json');
  
  return result;  */
  return {passed:'TODO'}
}




