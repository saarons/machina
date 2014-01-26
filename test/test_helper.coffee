chai = require("chai")
Assertion = chai.Assertion

sinon_chai = require("sinon-chai")
chai.use(sinon_chai)

express = require("express")
Machina = require("../machina")

Assertion.addProperty 'error_response', (resource = "people") ->
  new Assertion(@_obj).to.contain.keys("errors", resource)
  num_errors = @_obj[resource].count(null)
  new Assertion(@_obj.errors).to.have.length(num_errors)

module.exports =
  resource_methods:
    POST: "post"
    GET: "get"
    DELETE: "del"

  item_methods:
    GET: "get"
    PUT: "put"
    PATCH: "patch"
    DELETE: "del"

  test_adapter:
    find: (resource, keys, options, callback) -> callback(null, [{}])
    update: (resource, key, object, options, callback) -> callback(null, object)
    create: (resource, object, options, callback) -> callback(null, object)
    delete: (resource, keys, options, callback) -> callback(null, true)

  test_schema:
    type: "object"
    properties:
      first_name:
        type: "string"
      last_name:
        type: "string"
      age:
        type: "integer"
        minimum: 0
    required: ["first_name", "last_name"]

  setup: (context, options = {}) ->
    context.app = express()
    context.adapter = options.adapter || {}
    context.settings = options.settings || {}
    context.machina = new Machina
      adapter: context.adapter
      resources:
        people: context.settings
    context.app.use(express.json())
    context.app.use(context.machina.router())