sinon = require("sinon")
request = require("supertest")
expect = require("chai").expect
helpers = require("./test_helper")

describe "Adapter", ->
  describe "with default settings", ->
    beforeEach ->
      helpers.setup @

    describe "GET /<resource>", ->
      it "should call #find once", (done) ->
        stub = sinon.stub()          

        @adapter.find = stub.callsArgWith(3, null, [])

        request(@app)
          .get("/people")
          .end ->
            expect(stub).calledOnce
            done()

      it "should call #find with the proper arguments", (done) ->
        stub = sinon.stub()          

        @adapter.find = stub.callsArgWith(3, null, [])

        request(@app)
          .get("/people")
          .end ->
            expect(stub).calledWith("people", null, {}, sinon.match.func)
            done()