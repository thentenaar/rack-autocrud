rack-autocrud
=============

Rack middleware that works with Sinatra and DataMapper to dynamically
create CRUD endpoints and routes based on models. It ain't perfect, but
it works.

These generated CRUD routes are assumed to return a Rack response.

It's important to note, that you models and endpoints must be in separate
modules (read: namespaces).

Input and Response data are formatted as JSON.

Licensing
=========

This software is licensed under the [Simplified BSD License](http://en.wikipedia.org/wiki/BSD_licenses#2-clause_license_.28.22Simplified_BSD_License.22_or_.22FreeBSD_License.22.29) as described in the LICENSE file.

Requirements
============

* sinatra
* datamapper

Installation
============

    gem install rack-autocrud

Usage
=====

Just add something like this to your _config.ru_:

```ruby
require 'rack/autocrud'

# Load your models
require 'models'

# Load your endpoints
require 'endpoints'

# Auto-magical CRUD
run Rack::AutoCRUD.new nil, :model_namespace => 'Models', :endpoint_namespace => 'Endpoints'
```

This would assume you only want CRUD-based routing. You can also _use_ this middleware:

```ruby
use Rack::AutoCRUD, :model_namespace => 'Models', :endpoint_namespace => 'Endpoints'
```

How Routing Works
=================

The routing is simple. You have a model *Models::Person*. You've added something like the above to your
_config.ru_. This middleware will dynamically create a _Sinatra::Base_ subclass called *Endpoints::Person*
(if it already exists, these routes are added to it) which will contain the following routes:

| Route       |           Action               | HTTP Response Code |
| ----------- | -------------------------------| ------------------ |
| get /       | List all _Person_ entries      |      403           |
| post /      | Create a new _Person_          |      201 / 402     |
| get /:id    | Retrieve a _Person_            |      200           |
| put /:id    | Update a _Person_              |      201 / 403     |
| delete /:id | Destroy a _Person_             |      204           |

The middleware will route based on the URI. Thus, _/person_ would correspond to *Endpoints::Person*'s _get /_ route.

Overriding Generated Routes
===========================

You can define your own CRUD routes, which will be called and return a response
before the autogenerated routes, as long as they're added after your endpoint is defined.

For example:

```ruby
require 'sinatra/base'

module Endpoints
  class Person < Sinatra::Base
    get '/'
       Models::Person.all.to_json
    end
end
```

In this case, if you're using _dm-serializer_,you'd get back every _Models::Person_ record in the database in
a JSON array. By default, the _get /_ route returns "Access Denied."

CRUD Processing Hooks
=====================

There are some basic processing hooks you can define in your endpoint:

|             Hook               |                        Description                               |
| ------------------------------ | ---------------------------------------------------------------- |
| pre_create(env,request,obj)    | Called after the record is created, but before it's saved        |
| post_create(env,request,obj)   | Called after the record is saved, if it was saved successfully   |
| pre_retrieve(env,request)      | Called before the record is fetched                              |
| post_retrieve(env,request,obj) | Called after the record is fetched                               |
| pre_update(env,request)        | Called before the record is updated                              |
| post_update(env,request)       | Called after the record is updated, if it was saved successfully |
| pre_destroy(env,request)       | Called before the record is destroyed                            |
| post_destroy(env,request,obj)  | Called after the record is destroyed                             |

Parameters:

* *env* is the current Rack environment
* *request* is the current request object
* *obj* is the ORM object corresponding to the record in question

If any of these hooks returns anything other than _nil_, it is assumed to be a response object, which
is returned immediately, and no further processing is performed.


