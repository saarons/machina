sinon = require("sinon")
request = require("supertest")
helpers = require("./spec_helper")

describe "Adapter", ->
  describe "with default settings", ->
    beforeEach ->
      helpers.setup @

    describe "GET /<resource>", ->
      it "should call #find on the adapter with the proper arguments", (done) ->
        mock = sinon.mock(helpers.test_adapter)
        mock
          .expects("find")
          .once()
          .withArgs("people", null, {})
          .callsArgWith(3, null, [])

        @adapter.find = helpers.test_adapter.find

        request(@app)
          .get("/people")
          .end ->
            mock.verify()
            done()