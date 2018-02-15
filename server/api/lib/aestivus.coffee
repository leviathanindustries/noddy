
import connect from 'connect'
import connectRoute from 'connect-route'
import Fiber from 'fibers'
import Busboy from 'busboy'
import moment from 'moment'

@JsonRoutes = {}

WebApp.connectHandlers.use connect.urlencoded({limit: '1024mb'})
WebApp.connectHandlers.use connect.json({limit: '1024mb'})
WebApp.connectHandlers.use connect.query()

JsonRoutes.Middleware = JsonRoutes.middleWare = connect()
WebApp.connectHandlers.use JsonRoutes.Middleware

JsonRoutes.routes = []
@connectRouter
connectRouter = @connectRouter

WebApp.connectHandlers.use Meteor.bindEnvironment(connectRoute(( (router) -> connectRouter = router )))

# Error middleware must be added last, to catch errors from prior middleware.
# That's why we cache them and then add after startup.
errorMiddlewares = []
JsonRoutes.ErrorMiddleware =
  use: () ->
    errorMiddlewares.push arguments

Meteor.startup () ->
  _.each errorMiddlewares, ((errorMiddleware) ->
    errorMiddleware = _.map errorMiddleware, ((maybeFn) ->
      if _.isFunction maybeFn
        return (a, b, c, d) ->
          Meteor.bindEnvironment(maybeFn)(a, b, c, d);
      return maybeFn;
    )
    WebApp.connectHandlers.use.apply(WebApp.connectHandlers, errorMiddleware);
  )
  errorMiddlewares = []

JsonRoutes.add = (method, path, handler) ->
  path = '/' + path if path[0] isnt '/'
  JsonRoutes.routes.push {method: method, path: path}

  connectRouter[method.toLowerCase()] path, ((req, res, next) ->
    setHeaders res, responseHeaders
    Fiber(() ->
      try
        handler req, res, next
      catch error
        next error
    ).run()
  )


responseHeaders = 'Cache-Control': 'no-store', Pragma: 'no-cache'

JsonRoutes.setResponseHeaders = (headers) ->
  responseHeaders = headers

JsonRoutes.sendResult = (res, options={}) ->
  setHeaders(res, options.headers) if options.headers?
  res.statusCode = options.code || 200
  writeJsonToBody res, options.data
  res.end()

setHeaders = (res, headers) ->
  _.each headers, ((value, key) -> res.setHeader key, value )

writeJsonToBody = (res, json) ->
  if json?
    res.setHeader 'Content-type', 'application/json'
    res.write JSON.stringify(json, null, (if process.env.NODE_ENV is 'development' then 2 else null))




# TODO could make this only apply to certain routes, and handle it directly
JsonRoutes.Middleware.use (req, res, next) ->
  if req.headers?['content-type']?.match(/^multipart\/form\-data/)
    busboy = new Busboy {headers: req.headers}
    req.files = []

    busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
      uploadedFile = {
        filename,
        mimetype,
        encoding,
        fieldname,
        data: null
      }

      API.log msg: 'busboy have file...', uploadedFile, level: 'debug'
      buffers = []
      file.on 'data', (data) ->
        API.log msg: 'data length: ' + data.length, level: 'debug'
        buffers.push data
      file.on 'end', () ->
        console.log msg: 'End of busboy file', level: 'debug'
        uploadedFile.data = Buffer.concat buffers
        req.files.push uploadedFile

    busboy.on "field", (fieldname, value) -> req.body[fieldname] = value

    busboy.on 'finish', () -> next()

    req.pipe busboy
    return

  next()




ironRouterSendErrorToResponse = (err, req, res) ->
  res.statusCode = 500 if res.statusCode < 400
  res.statusCode = err.status if err.status
  msg = if (process.env.NODE_ENV ?= 'development') is 'development' then (err.stack || err.toString()) + '\n' else 'Server error.'
  console.error err.stack or err.toString()

  return req.socket.destroy() if res.headersSent

  res.setHeader 'Content-Type', 'text/html'
  res.setHeader 'Content-Length', Buffer.byteLength(msg)
  return res.end() if req.method is 'HEAD'

  res.end msg
  return




class share.Route

  constructor: (@api, @path, @options, @endpoints) ->
    # Check if options were provided
    if not @endpoints
      @endpoints = @options
      @options = {}


  addToApi: do ->
    availableMethods = ['get', 'post', 'put', 'patch', 'delete', 'options']

    return ->
      self = this

      # Throw an error if a route has already been added at this path
      # TODO: Check for collisions with paths that follow same pattern with different parameter names
      if _.contains @api._config.paths, @path
        throw new Error "Cannot add a route at an existing path: #{@path}"

      # Override the default OPTIONS endpoint with our own
      @endpoints = _.extend options: @api._config.defaultOptionsEndpoint, @endpoints

      # Configure each endpoint on this route
      @_resolveEndpoints()
      @_configureEndpoints()

      # Add to our list of existing paths
      @api._config.paths.push @path

      allowedMethods = _.filter availableMethods, (method) ->
        _.contains(_.keys(self.endpoints), method)
      rejectedMethods = _.reject availableMethods, (method) ->
        _.contains(_.keys(self.endpoints), method)

      # Setup endpoints on route
      fullPath = @api._config.apiPath + @path
      _.each allowedMethods, (method) ->
        endpoint = self.endpoints[method]
        @JsonRoutes.add method, fullPath, (req, res) ->
          # Add function to endpoint context for indicating a response has been initiated manually
          responseInitiated = false
          doneFunc = ->
            responseInitiated = true

          endpointContext =
            urlParams: req.params
            queryParams: req.query
            bodyParams: req.body
            request: req
            response: res
            done: doneFunc
          # Add endpoint config options to context
          _.extend endpointContext, endpoint

          # Run the requested endpoint
          responseData = null
          try
            responseData = self._callEndpoint endpointContext, endpoint
            if (responseData is null or responseData is undefined) and not responseInitiated
              responseData = 404
            if res.headersSent and not responseInitiated
              throw new Error "Must call this.done() after handling endpoint response manually: #{method} #{fullPath}"
          catch error
            # Do exactly what Iron Router would have done, to avoid changing the API
            ironRouterSendErrorToResponse(error, req, res);
            return

          if responseInitiated
            # Ensure the response is properly completed
            res.end()
            return

          # Generate and return the http response, handling the different endpoint response types
          if typeof responseData is 'number' and ((responseData >= 400 and responseData < 460) or (responseData >= 500 and responseData < 520))
            self._respond res, responseData, responseData
          else if responseData.body? and (responseData.statusCode or responseData.headers)
            self._respond res, responseData.body, responseData.statusCode, responseData.headers
          else
            self._respond res, responseData
      _.each rejectedMethods, (method) ->
        @JsonRoutes.add method, fullPath, (req, res) ->
          responseData = status: 'error', message: 'API endpoint does not exist'
          headers = 'Allow': allowedMethods.join(', ').toUpperCase()
          self._respond res, responseData, 405, headers


  ###
    Convert all endpoints on the given route into our expected endpoint object if it is a bare
    function

    @param {Route} route The route the endpoints belong to
  ###
  _resolveEndpoints: ->
    _.each @endpoints, (endpoint, method, endpoints) ->
      if _.isFunction(endpoint)
        endpoints[method] = {action: endpoint}
    return


  ###
    Configure the authentication and role requirement on all endpoints (except OPTIONS, which must
    be configured directly on the endpoint)

    Authentication can be required on an entire route or individual endpoints. If required on an
    entire route, that serves as the default. If required in any individual endpoints, that will
    override the default.

    After the endpoint is configured, all authentication and role requirements of an endpoint can be
    accessed at <code>endpoint.authRequired</code> and <code>endpoint.roleRequired</code>,
    respectively.

    @param {Route} route The route the endpoints belong to
    @param {Endpoint} endpoint The endpoint to configure
  ###
  _configureEndpoints: ->
    _.each @endpoints, (endpoint, method) ->
      if method isnt 'options'
        # Configure acceptable roles
        if not @options?.roleRequired
          @options.roleRequired = []
        if not endpoint.roleRequired
          endpoint.roleRequired = []
        endpoint.roleRequired = _.union endpoint.roleRequired, @options.roleRequired
        # Make it easier to check if no roles are required
        if _.isEmpty endpoint.roleRequired
          endpoint.roleRequired = false

        # Configure auth requirement
        if endpoint.authRequired is undefined
          if @options?.authRequired or endpoint.roleRequired
            endpoint.authRequired = true
          else
            endpoint.authRequired = false
        return
    , this
    return


  ###
    Authenticate an endpoint if required, and return the result of calling it

    @returns The endpoint response or a 401 if authentication fails
  ###
  _callEndpoint: (endpointContext, endpoint) ->
    # Call the endpoint if authentication doesn't fail
    if API.settings.log.connections and endpointContext.request.method isnt 'OPTIONS'
      tu = endpointContext.request.url.split('?')[0].split('#')[0]
      if tu.indexOf('_log') is -1 and tu.indexOf('/reload/') is -1
        API.log
          url: endpointContext.request.url.split('apikey=')[0], # TODO prob want to keep full URL with opts, or no opts, and remove apikey properly
          method: endpointContext.request.method,
          originalUrl: endpointContext.request.originalUrl, # TODO as above
          headers: endpointContext.request.headers, # TODO don't keep x-apikey if present
          query: endpointContext.request.query
      else if API.settings.log?.level is 'all'
        console.log 'Not creating log for query on a log URL, but logging to console because log level is all'
        console.log endpointContext.request.url, endpointContext.request.method, endpointContext.request.query, endpointContext.request.originalUrl

    if blacklisted = API.blacklist(endpointContext.request) isnt false
      return blacklisted
    else if @_authAccepted endpointContext, endpoint
      if @_roleAccepted endpointContext, endpoint
        endpoint.action.call endpointContext
      else
        statusCode: 403
        body: {status: 'error', message: 'You do not have permission to do this.'}
    else
      statusCode: 401
      body: {status: 'error', message: 'You must be logged in to do this.'}


  ###
    Authenticate the given endpoint if required

    Once it's globally configured in the API, authentication can be required on an entire route or
    individual endpoints. If required on an entire endpoint, that serves as the default. If required
    in any individual endpoints, that will override the default.

    @returns False if authentication fails, and true otherwise
  ###
  _authAccepted: (endpointContext, endpoint) ->
    if endpoint.authOptional
      @_authenticate endpointContext, true
    else if endpoint.authRequired
      @_authenticate endpointContext
    else true


  ###
    Verify the request is being made by an actively logged in user

    If verified, attach the authenticated user to the context.

    @returns {Boolean} True if the authentication was successful
  ###
  _authenticate: (endpointContext,optional) ->
    # Get auth info
    auth = @api._config.auth.user.call(endpointContext)

    # Get the user from the database
    if auth?.userId and auth?.token and not auth?.user
      userSelector = {}
      userSelector._id = auth.userId
      userSelector[@api._config.auth.token] = auth.token
      auth.user = API.accounts.retrieve userSelector

    # Attach the user and their ID to the context if the authentication was successful
    if auth?.user
      endpointContext.user = auth.user
      endpointContext.userId = auth.user._id
      rd = Date.now()
      if not auth.user.retrievedAt? or rd - auth.user.retrievedAt > 60000
        Users.update auth.user._id, {retrievedAt:rd, retrieved_date:moment(rd, "x").format("YYYY-MM-DD HHmm")}
      true
    else if optional
      true
    else false


  ###
    Authenticate the user role if required

    Must be called after _authAccepted().

    @returns True if the authenticated user belongs to <i>any</i> of the acceptable roles on the
             endpoint
  ###
  _roleAccepted: (endpointContext, endpoint) ->
    if endpoint.roleRequired
      return API.accounts.auth endpoint.roleRequired,endpointContext.user,endpoint.cascade
    true


  ###
    Respond to an HTTP request
  ###
  _respond: (response, body, statusCode=200, headers={}) ->
    # Override any default headers that have been provided (keys are normalized to be case insensitive)
    # TODO: Consider only lowercasing the header keys we need normalized, like Content-Type
    defaultHeaders = @_lowerCaseKeys @api._config.defaultHeaders
    headers = @_lowerCaseKeys headers
    headers = _.extend defaultHeaders, headers

    # Prepare JSON body for response when Content-Type indicates JSON type
    if headers['content-type'].match(/json|javascript/) isnt null
      if @api._config.prettyJson
        body = JSON.stringify body, undefined, 2
      else
        body = JSON.stringify body

    # Send response
    sendResponse = ->
      response.writeHead statusCode, headers
      response.write body
      response.end()
    if statusCode in [401, 403]
      # Hackers can measure the response time to determine things like whether the 401 response was
      # caused by bad user id vs bad password.
      # In doing so, they can first scan for valid user ids regardless of valid passwords.
      # Delay by a random amount to reduce the ability for a hacker to determine the response time.
      # See https://www.owasp.org/index.php/Blocking_Brute_Force_Attacks#Finding_Other_Countermeasures
      # See https://en.wikipedia.org/wiki/Timing_attack
      minimumDelayInMilliseconds = 500
      randomMultiplierBetweenOneAndTwo = 1 + Math.random()
      delayInMilliseconds = minimumDelayInMilliseconds * randomMultiplierBetweenOneAndTwo
      Meteor.setTimeout sendResponse, delayInMilliseconds
    else
      sendResponse()

  ###
    Return the object with all of the keys converted to lowercase
  ###
  _lowerCaseKeys: (object) ->
    _.chain object
    .pairs()
    .map (attr) ->
      [attr[0].toLowerCase(), attr[1]]
    .object()
    .value()



class @Restivus

  constructor: (options) ->
    @_routes = []
    @_config =
      paths: []
      apiPath: 'api/'
      version: null
      prettyJson: false
      auth:
        token: 'services.resume.loginTokens.hashedToken'
        user: ->
          if @request.headers['x-auth-token']
            token = API.accounts.hash @request.headers['x-auth-token']
          userId: @request.headers['x-user-id']
          token: token
      defaultHeaders:
        'Content-Type': 'application/json'
      enableCors: true

    # Configure API with the given options
    _.extend @_config, options

    if @_config.enableCors
      corsHeaders =
        'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, OPTIONS'
        'Access-Control-Allow-Origin': '*'
        #'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept'
        'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept, DNT, Keep-Alive, User-Agent, If-Modified-Since, Cache-Control'

      # Set default header to enable CORS if configured
      _.extend @_config.defaultHeaders, corsHeaders

      if not @_config.defaultOptionsEndpoint
        @_config.defaultOptionsEndpoint = ->
          @response.writeHead 200, corsHeaders
          @done()

    # Normalize the API path
    if @_config.apiPath[0] is '/'
      @_config.apiPath = @_config.apiPath.slice 1
    if _.last(@_config.apiPath) isnt '/'
      @_config.apiPath = @_config.apiPath + '/'

    # URL path versioning is the only type of API versioning currently available, so if a version is
    # provided, append it to the base path of the API
    if @_config.version
      @_config.apiPath += @_config.version + '/'

    return this


  add: (path, options, endpoints) ->
    # Create a new route and add it to our list of existing routes
    route = new share.Route(this, path, options, endpoints)
    @_routes.push(route)

    route.addToApi()

    return this
