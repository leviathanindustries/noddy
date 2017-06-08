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
        'Access-Control-Allow-Origin': '*'
        'Access-Control-Allow-Headers': 'Origin, X-Requested-With, Content-Type, Accept'

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


  ###*
    Add endpoints for the given HTTP methods at the given path

    @param path {String} The extended URL path (will be appended to base path of the API)
    @param options {Object} Route configuration options
    @param options.authRequired {Boolean} The default auth requirement for each endpoint on the route
    @param options.roleRequired {String or String[]} The default role required for each endpoint on the route
    @param endpoints {Object} A set of endpoints available on the new route (get, post, put, patch, delete, options)
    @param endpoints.<method> {Function or Object} If a function is provided, all default route
        configuration options will be applied to the endpoint. Otherwise an object with an `action`
        and all other route config options available. An `action` must be provided with the object.
  ###
  addRoute: (path, options, endpoints) ->
    # Create a new route and add it to our list of existing routes
    route = new share.Route(this, path, options, endpoints)
    @_routes.push(route)

    route.addToApi()

    return this


  ###*
    Generate routes for the Meteor Collection with the given name
  ###
  addCollection: (collection, options={}) ->
    methods = ['get', 'post', 'put', 'delete', 'getAll']
    methodsOnCollection = ['post', 'getAll']

    # Grab the set of endpoints
    collectionEndpoints = @_collectionEndpoints

    # Flatten the options and set defaults if necessary
    endpointsAwaitingConfiguration = options.endpoints or {}
    routeOptions = options.routeOptions or {}
    excludedEndpoints = options.excludedEndpoints or []
    # Use collection name as default path
    path = options.path or collection._name

    # Separate the requested endpoints by the route they belong to (one for operating on the entire
    # collection and one for operating on a single entity within the collection)
    collectionRouteEndpoints = {}
    entityRouteEndpoints = {}
    if _.isEmpty(endpointsAwaitingConfiguration) and _.isEmpty(excludedEndpoints)
      # Generate all endpoints on this collection
      _.each methods, (method) ->
        # Partition the endpoints into their respective routes
        if method in methodsOnCollection
          _.extend collectionRouteEndpoints, collectionEndpoints[method].call(this, collection)
        else _.extend entityRouteEndpoints, collectionEndpoints[method].call(this, collection)
        return
      , this
    else
      # Generate any endpoints that haven't been explicitly excluded
      _.each methods, (method) ->
        if method not in excludedEndpoints and endpointsAwaitingConfiguration[method] isnt false
          # Configure endpoint and map to it's http method
          # TODO: Consider predefining a map of methods to their http method type (e.g., getAll: get)
          endpointOptions = endpointsAwaitingConfiguration[method]
          configuredEndpoint = {}
          _.each collectionEndpoints[method].call(this, collection), (action, methodType) ->
            configuredEndpoint[methodType] =
              _.chain action
              .clone()
              .extend endpointOptions
              .value()
          # Partition the endpoints into their respective routes
          if method in methodsOnCollection
            _.extend collectionRouteEndpoints, configuredEndpoint
          else _.extend entityRouteEndpoints, configuredEndpoint
          return
      , this

    # Add the routes to the API
    @addRoute path, routeOptions, collectionRouteEndpoints
    @addRoute "#{path}/:id", routeOptions, entityRouteEndpoints

    return this


  ###*
    A set of endpoints that can be applied to a Collection Route
  ###
  _collectionEndpoints:
    get: (collection) ->
      get:
        action: ->
          entity = collection.findOne @urlParams.id
          if entity
            {status: 'success', data: entity}
          else
            statusCode: 404
            body: {status: 'fail', message: 'Item not found'}
    put: (collection) ->
      put:
        action: ->
          entityIsUpdated = collection.update @urlParams.id, @bodyParams
          if entityIsUpdated
            entity = collection.findOne @urlParams.id
            {status: 'success', data: entity}
          else
            statusCode: 404
            body: {status: 'fail', message: 'Item not found'}
    delete: (collection) ->
      delete:
        action: ->
          if collection.remove @urlParams.id
            {status: 'success', data: message: 'Item removed'}
          else
            statusCode: 404
            body: {status: 'fail', message: 'Item not found'}
    post: (collection) ->
      post:
        action: ->
          entityId = collection.insert @bodyParams
          entity = collection.findOne entityId
          if entity
            statusCode: 201
            body: {status: 'success', data: entity}
          else
            statusCode: 400
            body: {status: 'fail', message: 'No item added'}
    getAll: (collection) ->
      get:
        action: ->
          entities = collection.find().fetch()
          if entities
            {status: 'success', data: entities}
          else
            statusCode: 404
            body: {status: 'fail', message: 'Unable to retrieve items from collection'}

Restivus = @Restivus
