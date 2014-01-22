require("sugar")

tv4 = require("tv4")
async = require("async")
Router = require("express").Router
jsonpatch = require("fast-json-patch")
jsonpatchSchema = require("./jsonpatch")

defaults = 
  resource_methods: ["GET"]
  public_methods: []
  item_lookup: true
  item_methods: ["GET"]
  public_item_methods: []
  authorization: false
  server_name: "localhost:5000"
  url_prefix: ""
  api_version: "",
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

  buildSetupMiddleware: ->
    (req, res, next) ->
      req.machina = {}
      next()          

  buildAuthMiddleware: (authorization, public_methods, private_methods, method, resource) ->
    (req, res, next) =>
      if authorization
        if public_methods.indexOf(method) > -1 && private_methods.indexOf(method) > -1
          # If it's in both, we can authenticate but not error out if the auth fails
          @adapter.authorize req.get("Authorization"), resource, method, (err, authObject) ->
            req.machina.auth = authObject if !err && authObject
            next()
        else if private_methods.indexOf(method) > -1
          @adapter.authorize req.get("Authorization"), resource, method, (err, authObject) ->
            if err || !authObject
              res.send(401)
            else
              req.machina.auth = authObject
              next()
        else
          next()
      else
        next()

  buildMethodNotAllowedMiddleware: (config, method, type) -> 
    (req, res, next) =>
      item_methods = config.item_methods.union(config.public_item_methods)
      resource_methods = config.resource_methods.union(config.public_methods)

      if type == "resource" && resource_methods.indexOf(method) > -1
        next()
      else if type == "item" && config.item_lookup && item_methods.indexOf(method) > -1
        next()
      else
        res.send(405)

  router: ->
    @middleware ||= try
      router = new Router
        strict: false
        caseSensitive: true

      for resource, config of @options.resources
        config = @config(resource)

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

        for resource_method in ["GET", "POST", "DELETE"]
          authMiddleware = @buildAuthMiddleware(
            config.authorization,
            config.public_methods,
            config.resource_methods,
            resource_method,
            resource
          )
          methodNotAllowedMiddleware = @buildMethodNotAllowedMiddleware(config, resource_method, "resource")
          middleware = [@buildSetupMiddleware(), methodNotAllowedMiddleware, authMiddleware]

          switch resource_method
            when "GET" then router.get(resource_path, middleware, resource_GET)
            when "POST" then router.post(resource_path, middleware, resource_POST)
            when "DELETE" then router.delete(resource_path, middleware, resource_DELETE)

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

          validation_result = tv4.validateMultiple(req.body, jsonpatchSchema)
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

        for item_method in ["GET", "PATCH", "PUT", "DELETE"]
          methodNotAllowedMiddleware = @buildMethodNotAllowedMiddleware(config, item_method, "item")
          authMiddleware = @buildAuthMiddleware(
            config.authorization,
            config.item_methods,
            config.public_item_methods,
            item_method,
            resource
          )
          middleware = [@buildSetupMiddleware(), methodNotAllowedMiddleware, authMiddleware]

          item_path = "#{resource_path}/:lookup"

          switch item_method
            when "GET" then router.get(item_path, middleware, item_GET)
            when "PATCH" then router.patch(item_path, middleware, item_PATCH)
            when "PUT" then router.put(item_path, middleware, item_PUT)
            when "DELETE" then router.delete(item_path, middleware, item_DELETE)
        
      router.middleware