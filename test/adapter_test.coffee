sinon = require("sinon")
request = require("supertest")
expect = require("chai").expect
helpers = require("./test_helper")

describe "Adapter", ->
  describe "with default settings", ->
    beforeEach ->
      helpers.setup @

    describe "GET /<resource>", ->
      it "should call #find once with proper arguments", (done) ->
        stub = sinon.stub()          

        @adapter.find = stub.callsArgWith(3, null, [])

        request(@app)
          .get("/people")
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", null, {}, sinon.match.func)
            done()

    describe "GET /<resource>/<key>", ->
      it "should call #find once with proper arguments", (done) ->
        stub = sinon.stub()          

        @adapter.find = stub.callsArgWith(3, null, [])

        request(@app)
          .get("/people/1")
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", ["1"], {}, sinon.match.func)
            done()

  describe "with POST enabled", ->
    beforeEach ->
      helpers.setup @,
        settings:
          schema: helpers.test_schema
          resource_methods: ["POST"]

    describe "POST /<resource>", ->
      it "should call #create with proper arguments", (done) ->
        stub = sinon.stub()
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
        ]

        @adapter.create = stub.callsArgWith(3, null, {})

        request(@app)
          .post("/people")
          .send(payload)
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", payload[0], {}, sinon.match.func)
            done()

      it "should call #create multiple times with proper arguments", (done) ->
        stub = sinon.stub()
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        @adapter.create = stub.callsArgWith(3, null, {})

        request(@app)
          .post("/people")
          .send(payload)
          .end ->
            expect(stub).callCount(payload.length)
            for obj in payload
              expect(stub).calledWith("people", obj, {}, sinon.match.func)
            done()        
