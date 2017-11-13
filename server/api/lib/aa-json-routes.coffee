
import connect from 'connect'
import connectRoute from 'connect-route'
import Fiber from 'fibers'

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
