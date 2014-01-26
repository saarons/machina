require("sugar")

tv4 = require("tv4")
http = require("http")
async = require("async")
methods = require("methods")
Router = require("express").Router
jsonpatch = require("fast-json-patch")
jsonpatch_schema = require("./jsonpatch")

jsonpatch_url = 'https://raw.github.com/fge/sample-json-schemas/master/json-patch/json-patch.json'
put_schema = 
  type: "array"
  items: 
    $ref: jsonpatch_url

tv4.addSchema jsonpatch_url, jsonpatch_schema

http.IncomingMessage::real_method = ->
  override = @get("X-HTTP-Method-Override")
  if @method == "POST" && (override in ["PUT", "PATCH", "DELETE"])
    override
  else
    @method

defaults = 
  resource_methods: ["GET"]
  public_methods: []
  item_lookup: true
  item_methods: ["GET"]
  public_item_methods: []
  item_uri_template: null
  authentication: false
  server_name: "localhost:5000"
  url_prefix: null
  api_version: null,
  blacklist_paths: []
  blacklist_paths_on_update: []
  blacklist_paths_on_create: []

enhanced_merge = (target, source) ->
  Object.merge(Object.clone(target, true), source, true)

module.exports = class Application
  constructor: (options = {}) ->
    @options = enhanced_merge(defaults, options)
    @middleware = null
    @adapter = options.adapter

  config: (resource) ->
    enhanced_merge(@options, @options.resources[resource])

  sanitize: (resource, object) ->
    patches = @config(resource).blacklist_paths.map (path) ->
      {"op": "remove", path: path}
    jsonpatch.apply(object, patches)

  find: (resource, keys, options, callback) ->
    @adapter.find resource, keys, options, (err, results) =>
      if err
        callback(err, null)
      else
        @sanitize(resource, object) for object in results unless options.update
        callback(null, results)

  buildAuthMiddleware: (authentication, public_methods, private_methods, resource) ->
    (req, res, next) =>
      method = req.real_method()
      if authentication
        if public_methods.indexOf(method) > -1 && private_methods.indexOf(method) > -1
          # If it's in both, we can authenticate but not error out if the auth fails
          @adapter.authenticate req.get("Authorization"), (err, authObject) ->
            req.machina.auth = authObject unless err
            next()
        else if private_methods.indexOf(method) > -1
          @adapter.authenticate req.get("Authorization"), (err, authObject) ->
            if err
              res.send(401)
            else
              req.machina.auth = authObject
              next()
        else
          next()
      else
        next()

  buildMethodNotAllowedMiddleware: (config, type) -> 
    (req, res, next) =>
      item_methods = config.item_methods.union(config.public_item_methods)
      resource_methods = config.resource_methods.union(config.public_methods)

      if type == "resource" && resource_methods.indexOf(req.real_method()) > -1
        next()
      else if type == "item" && config.item_lookup && item_methods.indexOf(req.real_method()) > -1
        next()
      else
        res.send(405)

  build: ->
    router = new Router
      strict: false
      caseSensitive: true

    init = (req, res, next) ->
      req.machina = {}
      next()

    for resource of @options.resources
      do (config = @config(resource)) =>
        resource_path = "/#{resource}"
        resource_path = "/#{@options.api_version}" + resource_path if @options.api_version
        resource_path = "/#{@options.url_prefix}" + resource_path if @options.url_prefix

        resource_GET = (req, res) =>
          @find resource, null, req.machina, (err, results) ->
            if err
              res.send(500)
            else
              response = {}
              response[resource] = results
              res.json(response)

        resource_DELETE = (req, res) =>
          @adapter.delete resource, null, req.machina, (err, success) ->
            status_code = if err then 500
            else if success then 204
            else 422
            res.send(status_code)

        resource_POST = (req, res) =>
          createItem = (memo, item, callback) =>
            patches = config.blacklist_paths_on_create.map (path) ->
              {"op": "remove", path: path}

            jsonpatch.apply(item, patches)

            validation_result = tv4.validateMultiple(item, config.schema)

            if validation_result.valid
              @adapter.create resource, item, req.machina, (err, result) =>
                if err
                  memo[1].push(err)
                  memo[0].push(null)
                else
                  @sanitize(resource, result)
                  memo[0].push(result)
                callback(null, memo)
            else
              memo[1].push validation_result.errors
              memo[0].push(null)
              callback(null, memo)

          async.reduce req.body, [[],[]], createItem, (err, result) ->
            [results, errors] = result

            response = {}
            response.errors = errors unless errors.isEmpty()
            response[resource] = results

            if errors.isEmpty()
              res.send(201, response)
            else if response[resource].every((x) -> x == null)
              res.send(422, response)
            else
              res.send(207, response)

        resource_OPTIONS = (req, res) =>
          response = Object.clone(config.schema, true)
          response.links ||= []
          response.definitions ||= {}
          
          resource_methods =
            "GET": 
              method: "GET"
              rel: "instances"
              href: resource_path
            "POST":
              method: "POST"
              rel: "create"
              href: resource_path
              schema: 
                type: "array"
                items:
                  $ref: "#"
            "DELETE":
              method: "DELETE"
              rel: "destroy"
              href: resource_path

          item_path = "#{resource_path}/#{config.item_uri_template}"
          item_methods =
            "GET":
              method: "GET"
              rel: "self"
              href: item_path
            "PUT":
              method: "PUT"
              rel: "update"
              href: item_path
              schema:
                type: "array"
                items:
                  $ref: "#"
            "PATCH":
              method: "PATCH"
              rel: "update"
              href: item_path
              schema:
                $ref: "#/definitions/jsonpatch"
            "DELETE":
              method: "DELETE"
              rel: "destroy"
              href: item_path

          enabled_resource_methods = config.resource_methods.union(config.public_methods)
          for resource_method in enabled_resource_methods when resource_method isnt "OPTIONS"
            response.links.push(resource_methods[resource_method])

          if config.item_lookup && config.item_uri_template?
            enabled_item_methods = config.item_methods.union(config.public_item_methods)
            for item_method in enabled_item_methods when item_method isnt "OPTIONS"
              if item_method == "PATCH"
                response.definitions.jsonpatch = put_schema
              response.links.push(item_methods[item_method])

          res.json response

        resource_method_not_allowed_middlware = @buildMethodNotAllowedMiddleware(
          config, 
          "resource"
        )

        resource_auth_middleware = @buildAuthMiddleware(
          config.authentication,
          config.public_methods,
          config.resource_methods,
          resource
        )

        resource_middleware = [
          init,
          resource_method_not_allowed_middlware,
          resource_auth_middleware
        ]

        resource_endpoints =
          "GET": resource_GET
          "POST": resource_POST
          "DELETE": resource_DELETE
          "OPTIONS": resource_OPTIONS

        methods.each (method) ->
          router[method] resource_path, resource_middleware, (req, res) -> 
            resource_endpoints[req.real_method()](req, res)

        item_GET = (req, res) =>
          @find resource, [req.params.lookup], req.machina, (err, results) ->
            if err
              res.send(500)
            else
              response = {}
              response[resource] = results
              res.json(response)

        item_PATCH = (req, res) =>
          req.machina.update = true
          keys = [req.params.lookup]

          updateItem = (memo, item, callback) =>
            [object, patches, key] = item

            patches.remove (operation) ->
              config.blacklist_paths_on_update.some (path) ->
                operation.path.startsWith(path)

            if jsonpatch.apply(object, patches)
              validation_result = tv4.validateMultiple(object, config.schema)
              if validation_result.valid
                @adapter.update resource, key, object, req.machina, (err, result) =>
                  if err
                    memo[1].push(err)
                    memo[0].push(null)
                  else
                    @sanitize(resource, result)
                    memo[0].push(result)

                  callback(null, memo)
              else
                memo[1].push(validation_result.errors)
                memo[0].push(null)
                callback(null, memo)
            else
              memo[1].push(false)
              memo[0].push(null)
              callback(null, memo)

          validation_result = tv4.validateMultiple(req.body, put_schema)
          if validation_result.valid            
            @find resource, keys, req.machina, (err, results) ->
              if err
                res.send(500)
              else
                async.reduce results.zip(req.body, keys), [[],[]], updateItem, (err, result) ->
                  [results, errors] = result

                  response = {}
                  response.errors = errors unless errors.isEmpty()
                  response[resource] = results

                  if errors.isEmpty()
                    res.send(200, response)
                  else if response[resource].every((x) -> x == null)
                    res.send(422, response)
                  else
                    res.send(207, response)

            res.send(200)
          else
            res.json(400, {errors: validation_result.errors})

        item_PUT = (req, res) =>
          req.machina.update = true
          keys = req.params.lookup.split(",")

          updateItem = (memo, item, callback) =>
            [key, object] = item

            patches = config.blacklist_paths_on_update.map (path) ->
              {"op": "remove", path: path}

            jsonpatch.apply(object, patches)

            validation_result = tv4.validateMultiple(object, config.schema)
            if validation_result.valid
              @adapter.update resource, key, object, req.machina, (err, result) =>
                if err
                  memo[1].push(err)
                  memo[0].push(null)
                else
                  @sanitize(resource, result)
                  memo[0].push(result)

                callback(null, memo)
            else
              memo[1].push(validation_result.errors)
              memo[0].push(null)
              callback(null, memo)

          async.reduce keys.zip(req.body), [[], []], updateItem, (err, result) ->
            [results, errors] = result

            response = {}
            response.errors = errors unless errors.isEmpty()
            response[resource] = results

            if errors.isEmpty()
              res.send(200, response)
            else if response[resource].every((x) -> x == null)
              res.send(422, response)
            else
              res.send(207, response)

        item_DELETE = (req, res) =>
          keys = [req.params.lookup]

          @adapter.delete resource, keys, req.machina, (err, success) ->
            status_code = if err then 500
            else if success then 204
            else 422
            res.send(status_code)

        item_method_not_allowed_middleware = @buildMethodNotAllowedMiddleware(
          config, 
          "item"
        )

        item_auth_middleware = @buildAuthMiddleware(
          config.authentication,
          config.item_methods,
          config.public_item_methods,
          resource
        )

        item_middleware = [
          init,
          item_method_not_allowed_middleware,
          item_auth_middleware
        ]

        item_path = "#{resource_path}/:lookup"
        item_endpoints =
          "GET": item_GET
          "PUT": item_PUT
          "PATCH": item_PATCH
          "DELETE": item_DELETE
          "OPTIONS": resource_OPTIONS

        methods.each (method) ->
          router[method] item_path, item_middleware, (req, res) -> 
            item_endpoints[req.real_method()](req, res)

    router.middleware

  router: ->
    @middleware ||= @build()