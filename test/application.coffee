chai = require("chai")
sinon = require("sinon")
express = require("express")
request = require("supertest")
Machina = require("../machina")

expect = chai.expect
Assertion = chai.Assertion

Assertion.addProperty 'error_response', (resource = "people") ->
  new Assertion(@_obj).to.contain.keys("errors", resource)

  num_errors = @_obj[resource].count(null)
  new Assertion(@_obj.errors).to.have.length(num_errors)

resource_methods = 
  POST: "post"
  GET: "get"
  DELETE: "del"

item_methods = 
  GET: "get"
  PUT: "put"
  PATCH: "patch"
  DELETE: "del"

test_schema = 
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

setup = (context, options = {}) ->
  context.app = express()
  context.adapter = options.adapter || {}
  context.settings = options.settings || {}
  context.machina = new Machina
    adapter: context.adapter
    resources:
      people: context.settings
  context.app.use(express.json())
  context.app.use(context.machina.router())

describe "Application", ->
  describe "with default settings", ->
    beforeEach -> setup(@)

    describe "GET /<resource>", ->
      it "should return 200 when there is no error", (done) ->
        body = [
          {"id": 1, "name": "Sam"}
          {"id": 2, "name": "Bob"}
        ]
        @adapter.find = sinon.stub().callsArgWith(3, null, body)

        request(@app)
          .get("/people")
          .expect(200, {people: body}, done)

      it "should return 500 when an error occurs", (done) ->
        @adapter.find = sinon.stub().callsArgWith(3, true, null)

        request(@app)
          .get("/people")
          .expect(500, done)

    describe "GET /<resource>/<key>", ->
      it "should return 200 when there is no error", (done) ->
        body = [
          {"id": 1, "name": "Sam"}
        ]
        @adapter.find = sinon.stub().callsArgWith(3, null, body)

        request(@app)
          .get("/people")
          .expect(200, {people: body}, done)

    for verb, method of resource_methods when verb isnt "GET"
      describe "#{verb} /<resource>", ->
        it "should return 405", (done) ->
          request(@app)[method]("/people").expect(405, done)

    for verb, method of item_methods when verb isnt "GET"
      describe "#{verb} /<resource>/<key>", ->
        it "should return 405", (done) ->
          request(@app)[method]("/people/1").expect(405, done)

  describe "with authentication enabled", ->
    beforeEach -> 
      setup @,
        adapter:
          create: (resource, item, options, callback) -> callback(null, item)
          authenticate: (token, callback) -> 
            if token
              callback(null, true)
            else
              callback(true, null)
        settings:
          schema: test_schema
          authentication: true
          public_methods: ["GET"]
          resource_methods: ["POST"]

    describe "GET /<resource>", ->
      it "should return 200 even when no credentials are provided", (done) ->
        body = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, body)

        request(@app)
          .get("/people")
          .expect(200, {people: body}, done)

    describe "POST /<resource>", ->
      it "should return 401 when no credentials are provided", (done) ->
        request(@app)
          .post("/people")
          .expect(401, done)

      it "should return 201 when credentials are provided", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
        ]

        request(@app)
          .post("/people")
          .auth("sam", "keep_this_secret")
          .send(payload)
          .expect(201, done)

  describe "with blacklist_paths enabled", ->
    beforeEach ->
      setup @,
        adapter:
          create: (resource, item, options, callback) -> callback(null, item)
          update: (resource, key, object, options, callback) -> callback(null, object)
        settings:
          schema: test_schema
          blacklist_paths: ["/last_name"]
          resource_methods: ["GET", "POST"]
          item_methods: ["GET", "PUT", "PATCH"]

    describe "GET /<resource>", ->
      it "should sanitize paths properly", (done) ->
        body = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, body)

        expected = [
          {first_name: "Sam", age: 21},
          {first_name: "Etan", age: 22}
        ]

        request(@app)
          .get("/people")
          .expect(200, {people: expected}, done)

    describe "GET /<resource>/<key>", ->
      it "should sanitize paths properly", (done) ->
        body = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, body)

        expected = [
          {first_name: "Sam", age: 21},
        ]

        request(@app)
          .get("/people/sam")
          .expect(200, {people: expected}, done)

    describe "POST /<resource>", ->
      it "should sanitize paths properly", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
        ]

        expected = [
          {first_name: "Sam", age: 21}
        ]

        request(@app)
          .post("/people")
          .send(payload)
          .expect(201, {people: expected}, done)

    describe "PATCH /<resource>/<key>", ->
      it "should sanitize paths properly", (done) ->
        payload = [
          [
            {op: "replace", path: "/age", value: 22},
          ]
        ]

        records = [
          first_name: "Sam", last_name: "Aarons", age: 21
        ]

        expected = [
          first_name: "Sam", age: 22
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, records)

        request(@app)
          .patch("/people/sam")
          .send(payload)
          .expect(200, {people: expected}, done)

    describe "PUT /<resource>/<key>", ->
      it "should sanitize paths properly", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 22}
        ]

        expected = [
          {first_name: "Sam", age: 22}
        ]

        request(@app)
          .put("/people/sam")
          .send(payload)
          .expect(200, {people: expected}, done)

  describe "with item_lookup set to false", ->
    beforeEach ->
      setup @,
        settings:
          item_lookup: false
          item_methods: ["GET", "PATCH", "PUT", "DELETE"]        

    for verb, method of item_methods
      describe "#{verb} /<resource>/<key>", ->
        it "should return 405", (done) ->
          request(@app)[method]("/people/1").expect(405, done)

  describe "with OPTIONS enabled", ->
    beforeEach ->
      setup @,
        settings:
          schema: test_schema
          resource_methods: ["GET", "POST", "DELETE", "OPTIONS"]
          item_methods: ["GET", "PUT", "PATCH", "DELETE", "OPTIONS"]
          item_uri_template: "{last_name}"

    describe "OPTIONS /<resource>", ->
      it "should return 200", (done) ->
        request(@app)
          .options("/people")
          .expect(200, done)

    describe "OPTIONS /<resource>/<key>", ->
      it "should return 200", (done) ->
        request(@app)
          .options("/people/1")
          .expect(200, done)

  describe "with PUT enabled", ->
    beforeEach -> 
      setup @,
        adapter:
          update: (resource, key, object, options, callback) -> callback(null, object)
        settings:
          schema: test_schema
          item_methods: ["PUT"]

    describe "PUT /<resource>/<key>", ->
      it "should return 200 when the update is successful", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 22}
        ]

        request(@app)
          .put("/people/sam")
          .send(payload)
          .expect(200, {people: payload}, done)

      it "should return 200 when all updates are successful", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 22},
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        request(@app)
          .put("/people/sam,etan")
          .send(payload)
          .expect(200, {people: payload}, done)

      it "should return 422 when all updates are unsuccessful", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: -1},
          {first_name: "Etan", last_name: "Zapinsky", age: -1}
        ]

        request(@app)
          .put("/people/sam,etan")
          .send(payload)
          .expect 422, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

      it "should return 207 when some updates are successful", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 22},
          {first_name: "Etan", last_name: "Zapinsky", age: -1}
        ]

        request(@app)
          .put("/people/sam,etan")
          .send(payload)
          .expect 207, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

      it "should return 422 when the adapter returns an error on all documents", (done) ->
        error_message = "SKYNET HAS BEEN ACTIVATED"
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 22},
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        @adapter.update = (resource, key, object, options, callback) -> callback(error_message, null)

        request(@app)
          .put("/people/sam,etan")
          .send(payload)
          .expect 422, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

  describe "with PATCH enabled", ->
    beforeEach ->
      setup @,
        adapter:
          update: (resource, key, object, options, callback) -> callback(null, object)
        settings:
          schema: test_schema
          item_methods: ["PATCH"]

    describe "PATCH /<resource>/<key>", ->
      it "should return 200 when the update is successful", (done) ->
        payload = [
          [
            {op: "replace", path: "/age", value: 22}
          ]
        ]

        records = [
          first_name: "Sam", last_name: "Aarons", age: 21
        ]

        expected = [
          first_name: "Sam", last_name: "Aarons", age: 22 
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, records)

        request(@app)
          .patch("/people/sam")
          .send(payload)
          .expect(200, {people: expected}, done)

      it "should return 200 when all the updates are successful", (done) ->
        payload = [
          [
            {op: "replace", path: "/age", value: 22}
          ],
          [
            {op: "replace", path: "/age", value: 22}
          ]
        ]

        records = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
          {first_name: "Etan", last_name: "Zapinsky", age: 21}
        ]

        expected = [
          {first_name: "Sam", last_name: "Aarons", age: 22}
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, records)

        request(@app)
          .patch("/people/sam,etan") # TODO(saarons): standardize on some sort of syntax
          .send(payload)
          .expect(200, {people: expected}, done)

      it "should return 422 when all updates are unsuccessful", (done) ->
        payload = [
          [
            {op: "replace", path: "/age", value: -1}
          ],
          [
            {op: "replace", path: "/age", value: -1}
          ]
        ]

        records = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
          {first_name: "Etan", last_name: "Zapinsky", age: 21}
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, records)

        request(@app)
          .patch("/people/sam,etan")
          .send(payload)
          .expect 422, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

      it "should return 207 when some updates are successful", (done) ->
        payload = [
          [
            {op: "replace", path: "/age", value: 22}
          ],
          [
            {op: "replace", path: "/age", value: -1}
          ]
        ]

        records = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
          {first_name: "Etan", last_name: "Zapinsky", age: 21}
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, records)

        request(@app)
          .patch("/people/sam,etan")
          .send(payload)
          .expect 207, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

      it "should return 400 when the payload is not a JSON patch", (done) ->
        payload = ["BANANAS"]

        request(@app)
          .patch("/people/sam")
          .send(payload)
          .expect(400, done)

      it "should return 422 when the adapter returns an error on all documents", (done) ->
        error_message = "SKYNET HAS BEEN ACTIVATED"

        payload = [
          [
            {op: "replace", path: "/age", value: 22}
          ],
          [
            {op: "replace", path: "/age", value: 22}
          ]
        ]

        records = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
          {first_name: "Etan", last_name: "Zapinsky", age: 21}
        ]

        @adapter.find = sinon.stub().callsArgWith(3, null, records)
        @adapter.update = (resource, key, object, options, callback) ->
          callback(error_message, null)

        request(@app)
          .patch("/people/sam,etan")
          .send(payload)
          .expect 422, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

  describe "with POST enabled", ->
    beforeEach ->
      setup @,
        adapter:
          create: (resource, item, options, callback) -> callback(null, item)
        settings:
          schema: test_schema
          resource_methods: ["POST"]        

    describe "POST /<resource>", ->
      it "should return 201 when the document is valid", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
        ]

        request(@app)
          .post("/people")
          .send(payload)
          .expect(201, {people: payload}, done)

      it "should return 201 when all documents are valid", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
          {first_name: "Etan", last_name: "Zapinsky", age: 21}
        ]

        request(@app)
          .post("/people")
          .send(payload)
          .expect(201, {people: payload}, done)

      it "should return 422 when all documents are invalid", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: -1},
          {first_name: "Etan", last_name: "Zapinsky", age: -1}
        ]

        request(@app)
          .post("/people")
          .send(payload)
          .expect 422, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

      it "should return 207 when some documents are valid", (done) ->
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
          {first_name: "Etan", last_name: "Zapinsky", age: -1}
        ]

        request(@app)
          .post("/people")
          .send(payload)
          .expect 207, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

      it "should return 422 when the adapter returns an error on all documents", (done) ->
        error_message = "SKYNET HAS BEEN ACTIVATED"
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
          {first_name: "Etan", last_name: "Zapinsky", age: 21}          
        ]
        @adapter.create = (resource, item, options, callback) -> callback(error_message, null)

        request(@app)
          .post("/people")
          .send(payload)
          .expect 422, (err, res) ->
            expect(res.body).to.be.an.error_response
            done()

  describe "with DELETE enabled", ->
    beforeEach ->
      setup @,
        settings:
          item_methods: ["DELETE"]
          resource_methods: ["DELETE"]

    paths =
      "/<resource>": "/people"
      "/<resource>/<key>": "/people/1"

    for path, actual_path of paths
      describe "DELETE #{path}", ->
        it "should return 204 when there is no error", (done) ->
          @adapter.delete = sinon.stub().callsArgWith(3, null, true)

          request(@app)
            .del(actual_path)
            .expect(204, done)

        it "should return 422 when the adapter returns false", (done) ->
          @adapter.delete = sinon.stub().callsArgWith(3, null, false)

          request(@app)
            .del(actual_path)
            .expect(422, done)

        it "should return 500 when an error occurs", (done) ->
          @adapter.delete = sinon.stub().callsArgWith(3, {}, false)

          request(@app)
            .del(actual_path)
            .expect(500, done)