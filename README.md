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

app = express()
framework = new Machina
  adapter:
    find: (resource, keys, options, callback) -> # Your app logic goes here
  resources:
    people: {}
app.use(express.json())
app.use(framework.router())
```