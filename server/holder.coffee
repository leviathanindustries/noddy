

# an endpoint that can be passed a URL of a csv or google sheet, or POSTed some data, and create an index and holder UI for it

# should this create new types in an overall holder index, or should it be complete new indexes for every new thing holder holds?
# remember ES now (maybe always) won't allow key type clashes across index types... so may have to be whole new indexes. Or per user???

# could create an object of holder collection items, so they are ready for use - would need to check if not in there on some query that they were 
# not previously created in a different server / uptime, and so would check the index and make them if not already available

'''
holder_config = new API.collection index: API.settings.es.index + "_holder", type: "config"
_holders = {} # create new holder collections in here

API.holder = {}

API.add 'holder', 
  get: () -> 
    return
      statusCode: 200
      headers:
        'Content-Type': 'text/html'
      body: API.holder.configure()

API.add 'holder/:type',
  get: () -> # for now view is public
    if this.urlParams.type isnt 'config' and holder_config.get(this.urlParams.type)?
      return
        statusCode: 200
        headers:
          'Content-Type': 'text/html'
        body: API.holder.view this.urlParams.type
    else
      return 404
  post:
    roleRequired: 'holder.admin' # could be the role of the creator of the type
    action: () -> 
      # create from csv upload or url, gsheet url, json data post, or on existing index
      # if csv/json upload, get the content from the file first? Or leave to the method?
      return API.holder.create this.urlParams.type, this.bodyParams
  delete:
    roleRequired: 'root'
    action: () -> return data: 'Should delete the given datatype'

API.add 'holder/:type/move/:from/:to', get: () -> return 'Should move a named field to another name'
API.add 'holder/:type/copy/:from/:to', get: () -> return 'Should copy a named field to another name'

API.add 'holder/:type/map',
  get: () -> return data: 'Should provide the mapping for the datatype' # unless mount can provide this more easily
  post: () -> return data: 'Should create and map the datatype. If already existing, remap? Or refuse?'

API.add 'holder/:type/query',
  get: () ->
    if this.urlParams.type.indexOf(',') isnt -1
      q = API.collection._translate this
      res = API.es.call 'GET', API.settings.es.index + '_holder/' + this.urlParams.type + '/_search?' + (if q.indexOf('?') is 0 then q.replace('?', '') else q)
      res.q = q if API.settings.dev
      return res
    else
      if holder_config.get(this.urlParams.type)? and not _holders[type]?
        _holders[type] = new API.collection index: API.settings.es.index + "_holder", type: type
      return _holders[type].search this
  post: () ->
    if this.urlParams.type.indexOf(',') isnt -1
      q = API.collection._translate this
      res = API.es.call 'POST', API.settings.es.index + '_holder/' + this.urlParams.type + '/_search', q
      res.q = q if API.settings.dev
      return res
    else
      if holder_config.get(this.urlParams.type)? and not _holders[type]?
        _holders[type] = new API.collection index: API.settings.es.index + "_holder", type: type
      return _holders[type].search this

# later add ways to control access to the query and view endpoints, by groups and ability to put users into those groups
# e.g. if a group named holder_INDEX exists, use the group admin controls and see if the given user is in that group
# but if the group does not exist, allow anyone

# later add a create and edit form



API.holder.indexes = (dev=API.settings.dev) ->
  indexes = []
  for i in API.es.indexes()
    indexes.push(i.replace('_holder','').replace('_dev','')) if i.indexOf('_holder_') isnt -1 and ((dev and i.indexOf('_dev_') isnt -1) or (not dev and i.indexOf('_dev_') is -1))
  return indexes

API.holder.types = (index=API.settings.es.index + '_holder', dev=API.settings.dev) ->
  types = []
  index += '_dev' if dev and index.indexOf('_dev') is -1
  for i in API.es.types index
    types.push(i) if i isnt 'config'
  return types
  
API.holder.config = (type, config) ->
  if config
    config._id = type
    holder_config.insert config
    return config
  else if c = holder_config.get type
    return c
  else
    return undefined

API.holder.create = (type, config) ->
  return false if holder_config.get(type)? # if it exists should it just create with some unique id added to the provided name?
  _holders[type] = new API.collection index: API.settings.es.index + "_holder", type: type # should maybe check to see if a mapping was provided in config
  if _holders[type]?
    records = []
    if config?.source?
      if config.source.indexOf('http') is 0
        if config.source.indexOf('/spreadsheets/d') isnt -1
          # get it from the google sheet feed
          records = API.use.google.sheets.feed config.source
        else if config.source.indexOf('.') isnt -1 and config.source.split('.').pop().split('?')[0].split('#')[0].toLowerCase() is 'csv'
          records = API.convert.csv2json config.source
        else
          try records = JSON.parse HTTP.get(config.source).content
      else if typeof object.source is 'object' and _.isArray object.source
        records = object.source
        # if saving the config, it would have to be saved as a string type to match others... should prob just switch it to just being a statement about being provided as raw data
        # the source contains data to be loaded to start with
        delete object.source
        object.upload = true
        # should a file upload be dumped into here, or should it be handled explicitly?
      else
        records = []
        # it could be a sheet ID or the name of a pre-existing noddy index/type?
    if records.length
      try _holders[type].import records
      config.started = records.length
    holder_config.insert type, config
    return true # any useful info to return?
  else
    return undefined

API.holder.remove = (type) ->
  return true

_head = '<!DOCTYPE html>
<html dir="ltr" lang="en">
  <head>
    <meta charset="utf-8">
    <title>Holder API {{type}}</title>
    <meta name="description" content="">
    <meta name="author" content="Cottage Labs">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- Le HTML5 shim, for IE6-8 support of HTML elements -->
    <!--[if lt IE 9]>
      <script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
    <![endif]-->

    <script type="text/javascript" src="//static.cottagelabs.com/jquery-1.10.2.min.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/d3/d3.v4.min.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/bootstrap-3.0.3/js/bootstrap.min.js"></script>
    <link rel="stylesheet" href="//static.cottagelabs.com/bootstrap-3.0.3/css/bootstrap.min.css">
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/jquery.holder.js"></script>

    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/chart.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/datatables.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/export.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/facets.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/filters.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/graph.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/line.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/map.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/network.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/range.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/sankey.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/scotland.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/uk.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/display/world.js"></script>
    
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/use/export.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/use/doaj.js"></script>

    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/use/cl/crossref.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/use/cl/exlibris.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/use/cl/opendoar.js"></script>
    <script type="text/javascript" src="//static.cottagelabs.com/holdernew/use/cl/share.js"></script>

    <style>
      {{style}}
    </style>
  </head>'

API.holder.view = (type) ->
  # build the html page UI for the given type
  config = API.holder.config type
  style = '' # read this from config, could be custom css, and insert into head
  return _head.replace('{{style}}',style).replace('{{type}}',type) + '
  <body>
    <div class="container-fluid" style="max-width:1000px;margin:10px auto 10px auto;">
      <div class="row">
        <div id="holder" class="col-md-12"></div>
      </div>
    </div>
  </body>
  
  <script>
  jQuery(document).ready(function() {
    $("#holder").holder();
  });
  </script>
</html>'

API.holder.configure = (type='configure') ->
  # build the html config UI for the given type
  # or a blank one to create a new type
  if type isnt 'configure' and config = API.holder.config(type)
    domethingwithconfig = true
  return _head.replace('{{style}}','').replace('{{type}}',type) + '
  <body>
    <div class="container-fluid" style="max-width:1000px;margin:10px auto 10px auto;">
      <div class="row">
        <div class="col-md-12">
          <input type="text" id="name" placeholder="name" class="form-control">
          <div class="row">
            <div class="col-md-6" id="displays"></div>
            <div class="col-md-6" id="uses"></div>
          </div>
          <p><input type="text" id="source" placeholder="source" class="form-control">
          or <a id="upload" href="#">upload a file</a></p>
          <p><a href="#" id="create" class="btn btn-info">create</a></p>
        </div>
      </div>
    </div>
  </body>
  
  <script>
  jQuery(document).ready(function() {
    for (var d in $.fn.holder.display) {
      $("#displays").append(\'<p><input type="checkbox" class="display" value="\' + d + \'"> \' + d + \'</p>\');
    }
    for (var u in $.fn.holder.use) {
      $("#uses").append(\'<p><input type="checkbox" class="use" value="\' + u + \'"> \' + u + \'</p>\');
    }
    var create = function(e) {
      e.preventDefault();
      var settings = {
        name: $("#name").val(),
        source: $("#source").val(),
        displays: [],
        uses: []
      };
      settings.endpoint = settings.name.toLowerCase().trim().replace(/ /g,"_");
      $(".displays:checked").each(function() { settings.displays.push( $(this).val() ); });
      $(".uses:checked").each(function() { settings.uses.push( $(this).val() ); });
      $.ajax({
        url: window.location.href + "/" + settings.endpoint,
        type: "POST",
        data: settings,
        success: function(d) {
          window.location = window.location.href + "/" + settings.endpoint
        }
      });
    };
    $("#create").bind("click",create);
  });
  </script>
</html>'
'''
