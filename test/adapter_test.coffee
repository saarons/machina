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