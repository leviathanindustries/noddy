
###
API.add 'convert/test',
  get:
    roleRequired: if API.settings.dev then undefined else 'root'
    action: () -> return API.convert.test this.queryParams.fixtures


API.convert.test = (fixtures) ->

  console.log('Starting convert test') if API.settings.dev

  if (fixtures === undefined && API.settings.fixtures && API.settings.fixtures.url) fixtures = API.settings.fixtures.url;
  if (fixtures === undefined) return {passed: false, failed: [], NOTE: 'fixtures.url MUST BE PROVIDED IN SETTINGS FOR THIS TEST TO RUN, and must point to a folder containing files called test in csv, html, pdf, xml and json format'}

  var result = {failed:[]};

  result.csv2json = API.convert.run(fixtures + 'test.csv','csv','json');

  result.table2json = API.convert.run(fixtures + 'test.html','table','json');

  result.html2txt = API.convert.run(fixtures + 'test.html','html','txt');

  //result.file2txt = API.convert.run(fixtures + 'test.doc','file','txt');

  result.pdf2txt = API.convert.run(fixtures + 'test.doc','pdf','txt');

  result.xml2txt = API.convert.run(fixtures + 'test.xml','xml','txt');

  result.xml2json = API.convert.run(fixtures + 'test.xml','xml','json');

  result.json2csv = API.convert.run(fixtures + 'test.json','json','csv');

  result.json2json = API.convert.run(fixtures + 'test.json','json','json');

  result.passed = result.passed isnt false and result.failed.length is 0
  
  console.log('Ending collection test') if API.settings.dev

  return result



###