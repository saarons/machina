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

      it "should call #find once with proper arguments", (done) ->
        stub = sinon.stub()          

        @adapter.find = stub.callsArgWith(3, null, [])

        request(@app)
          .get("/people/1,2")
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", ["1", "2"], {}, sinon.match.func)
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

  describe "with DELETE enabled", ->
    beforeEach ->
      helpers.setup @,
        settings:
          item_methods: ["DELETE"]
          resource_methods: ["DELETE"]

    describe "DELETE /<resource>", ->
      it "should call #delete with the proper arguments", (done) ->
        stub = sinon.stub()

        @adapter.delete = stub.callsArgWith(3, null, true)

        request(@app)
          .del("/people")
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", null, {}, sinon.match.func)
            done()

    describe "DELETE /<resource>/<key>", ->
      it "should call #delete with the proper arguments", (done) ->
        stub = sinon.stub()

        @adapter.delete = stub.callsArgWith(3, null, true)

        request(@app)
          .del("/people/1")
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", ["1"], {}, sinon.match.func)
            done()

      it "should call #delete once with the proper arguments", (done) ->
        stub = sinon.stub()

        @adapter.delete = stub.callsArgWith(3, null, true)

        request(@app)
          .del("/people/1,2")
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", ["1", "2"], {}, sinon.match.func)
            done()

  describe "with PUT enabled", ->
    beforeEach ->
      helpers.setup @,
        settings:
          item_methods: ["PUT"]
          schema: helpers.test_schema

    describe "PUT /<resource>/<key>", ->
      it "should call #update with the proper arguments", (done) ->
        stub = sinon.stub()
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21}
        ]

        @adapter.update = stub.callsArgWith(4, null, {})

        request(@app)
          .put("/people/1")
          .send(payload)
          .end ->
            expect(stub).calledOnce
            expect(stub).calledWith("people", "1", payload[0], {update: true}, sinon.match.func)
            done()

      it "should call #update multiple times with the proper arguments", (done) ->
        stub = sinon.stub()
        ids = ["1", "2"]
        payload = [
          {first_name: "Sam", last_name: "Aarons", age: 21},
          {first_name: "Etan", last_name: "Zapinsky", age: 22}
        ]

        @adapter.update = stub.callsArgWith(4, null, {})

        request(@app)
          .put("/people/1,2")
          .send(payload)
          .end ->
            expect(stub).callCount(payload.length)
            for obj in payload.zip(ids)
              expect(stub).calledWith("people", obj[1], obj[0], {update: true}, sinon.match.func)
            done()

  describe "with PATCH enabled", ->
    beforeEach ->
      helpers.setup @,
        settings:
          item_methods: ["PATCH"]
          schema: helpers.test_schema

    describe "PATCH /<resource>/<key>", ->
      it "should call #find once and #update once with proper arguments", (done) ->
        find_stub = sinon.stub()
        update_stub = sinon.stub()

        payload = [
          [
            {op: "replace", path: "/age", value: 21}
          ]
        ]

        records = [
          {first_name: "Sam", last_name: "Aarons", age: 22}
        ]

        @adapter.find = find_stub.callsArgWith(3, null, records)
        @adapter.update = update_stub.callsArgWith(4, null, {})

        request(@app)
          .patch("/people/1")
          .send(payload)
          .end ->
            expect(find_stub).calledOnce
            expect(find_stub).calledWith("people", ["1"], {update: true}, sinon.match.func)

            expect(update_stub).calledOnce
            expect(update_stub).calledWith("people", "1", records[0], {update: true}, sinon.match.func)

            done()

      it "should call #find once and #update multiple times with proper arguments", (done) ->
        find_stub = sinon.stub()
        update_stub = sinon.stub()

        ids = ["1", "2"]
        payload = [
          [
            {op: "replace", path: "/age", value: 21}
          ],
          [
            {op: "replace", path: "/age", value: 22}
          ]
        ]

        records = [
          {first_name: "Sam", last_name: "Aarons", age: 22}
          {first_name: "Etan", last_name: "Zapinsky", age: 21}
        ]

        @adapter.find = find_stub.callsArgWith(3, null, records)
        @adapter.update = update_stub.callsArgWith(4, null, {})

        request(@app)
          .patch("/people/1,2")
          .send(payload)
          .end ->
            expect(find_stub).calledOnce
            expect(find_stub).calledWith("people", ids, {update: true}, sinon.match.func)

            expect(update_stub).callCount(records.length)

            for obj in records.zip(ids)
              expect(update_stub).calledWith("people", obj[1], obj[0], {update: true}, sinon.match.func)

            done()
