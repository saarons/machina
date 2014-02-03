# machina [![Build Status](https://travis-ci.org/saarons/machina.png?branch=master)](https://travis-ci.org/saarons/machina)

machina is a highly configurable, out-of-the-box microframework that exposes an entire JSON REST API. machina draws
heavily from [Eve](http://python-eve.org/) and [Fortune.js](http://fortunejs.com/) and combines the best features 
from both.

## Installation

    $ npm install machina

## Getting Started

```coffee
express = require("express")
Machina = require("machina")

db = [
  {id: "1", first_name: "Sam", last_name: "Aarons", age: 21},
  {id: "2", first_name: "Etan", last_name: "Zapinsky", age: 22}
]

app = express()
framework = new Machina
  adapter:
    find: (resource, keys, options, callback) -> 
      if keys
        results = []
        for record in db when keys.indexOf(record.id) > -1
          results.push(record)
        callback(null, results)
      else
        callback(null, db)
  resources:
    people: {}
app.use(express.json())
app.use(framework.router())
```