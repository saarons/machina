require("sugar")

tv4 = require("tv4")
http = require("http")
_ = require("highland")
express = require("express")
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
  mount_prefix: null
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
    top_level_router = express.Router()

    top_level_router.use (req, res, next) ->
      req.machina = {}
      next()

    for resource of @options.resources
      do (resource, config = @config(resource)) =>
        resource_path = "/#{resource}"

        router = express.Router()
        top_level_router.use(resource_path, router)

        multi_response = (res, success_code, error_code) ->
          results = []
          errors = []

          (err, x, push, next) ->
            if (err)
              results.push(null)
              errors.push(err)
              next()
            else if x == _.nil
              response = {}
              response.errors = errors unless errors.isEmpty()
              response[resource] = results

              if errors.isEmpty()
                res.send(success_code, response)
              else if response[resource].every(null)
                res.send(error_code, response)
              else
                res.send(207, response)

              push(null, x)
            else
              results.push(x)
              next()

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
          createItem = (err, item, push, next) =>
            if err
              push(err)
              next()
            else if item == _.nil
              push(null, item)
            else
              patches = config.blacklist_paths_on_create.map (path) ->
                {"op": "remove", path: path}

              jsonpatch.apply(item, patches)

              validation_result = tv4.validateMultiple(item, config.schema)

              if validation_result.valid
                @adapter.create resource, item, req.machina, (err, result) =>
                  if err
                    push(err)
                  else
                    @sanitize(resource, result)
                    push(null, result)
                  next()
              else
                push(validation_result.errors)
                next()

          _(req.body).consume(createItem).consume(multi_response(res, 201, 422)).resume()

        resource_OPTIONS = (req, res) =>
          response = Object.clone(config.schema, true)
          response.links ||= []
          response.definitions ||= {}

          actual_resource_path = resource_path
          actual_resource_path = config.mount_prefix + resource_path if config.mount_prefix
          
          resource_methods =
            "GET": 
              method: "GET"
              rel: "instances"
              href: actual_resource_path
            "POST":
              method: "POST"
              rel: "create"
              href: actual_resource_path
              schema: 
                type: "array"
                items:
                  $ref: "#"
            "DELETE":
              method: "DELETE"
              rel: "destroy"
              href: actual_resource_path

          item_path = "#{actual_resource_path}/#{config.item_uri_template}"
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
          resource_method_not_allowed_middlware,
          resource_auth_middleware
        ]

        resource_endpoints =
          "GET": resource_GET
          "POST": resource_POST
          "DELETE": resource_DELETE
          "OPTIONS": resource_OPTIONS

        router.route("/").all resource_middleware, (req, res, next) ->
          resource_endpoints[req.real_method()](req, res)

        item_GET = (req, res) =>
          @find resource, req.params.lookup.split(","), req.machina, (err, results) ->
            if err
              res.send(500)
            else
              response = {}
              response[resource] = results
              res.json(response)

        item_PATCH = (req, res) =>
          req.machina.update = true
          keys = req.params.lookup.split(",")

          updateItem = (err, item, push, next) =>
            if err
              push(err)
              next()
            else if item == _.nil
              push(null, item)
            else
              [object, patches, key] = item

              patches.remove (operation) ->
                config.blacklist_paths_on_update.some (path) ->
                  operation.path.startsWith(path)

              if jsonpatch.apply(object, patches)
                validation_result = tv4.validateMultiple(object, config.schema)
                if validation_result.valid
                  @adapter.update resource, key, object, req.machina, (err, result) =>
                    if err
                      push(err)
                    else
                      @sanitize(resource, result)
                      push(null, result)

                    next()
                else
                  push(validation_result.errors)
                  next()
              else
                push(null, false)
                next()

          validation_result = tv4.validateMultiple(req.body, put_schema)
          if validation_result.valid            
            @find resource, keys, req.machina, (err, results) ->
              if err
                res.send(500)
              else
                _(results.zip(req.body, keys)).consume(updateItem).consume(multi_response(res, 200, 422)).resume()
          else
            res.json(400, {errors: validation_result.errors})

        item_PUT = (req, res) =>
          req.machina.update = true
          keys = req.params.lookup.split(",")

          updateItem = (err, item, push, next) =>
            if err
              push(err)
              next()
            else if item == _.nil
              push(null, item)
            else
              [key, object] = item

              patches = config.blacklist_paths_on_update.map (path) ->
                {"op": "remove", path: path}

              jsonpatch.apply(object, patches)

              validation_result = tv4.validateMultiple(object, config.schema)
              if validation_result.valid
                @adapter.update resource, key, object, req.machina, (err, result) =>
                  if err
                    push(err)
                  else
                    @sanitize(resource, result)
                    push(null, result)

                  next()
              else
                push(validation_result.errors)
                next()

          _(keys.zip(req.body)).consume(updateItem).consume(multi_response(res, 200, 422)).resume()

        item_DELETE = (req, res) =>
          keys = req.params.lookup.split(",")

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
          item_method_not_allowed_middleware,
          item_auth_middleware
        ]

        item_endpoints =
          "GET": item_GET
          "PUT": item_PUT
          "PATCH": item_PATCH
          "DELETE": item_DELETE
          "OPTIONS": resource_OPTIONS

        router.route("/:lookup").all item_middleware, (req, res, next) ->
          item_endpoints[req.real_method()](req, res)
            

    return top_level_router

  router: ->
    @middleware ||= @build()