redim
=====

Redim is a simple Node.js ORM for Redis. The usual gamut of ORM operations
is available, as well as model instance event listeners using Redis's
PUBLISH/SUBSCRIBE functionality.

Getting started
---------------

    npm install redim

Javascript:
    
    var redim = require('redim');
    redim.createClient();                          // Takes the same options as redis.createClient()


Creating models, create, saving, deleting instances
--------------

Javascript:

    var redim = require('redim');
    newModel = new redim.Model('newModel',  // Model name
        ['name', 'email', 'category'],      // Model fields
        ['email']);                         // Index fields, optional

    newData = {
        name: 'Derek',
        email: 'derek@derekarnold.net',
        category: 'Meat Popsicle'
        };
    newModel.create(newData, function (result) {
        console.log(newResult.id);          // Outputs 1
        console.log(result.name);           // Outputs 'Derek'
        result.name = 'Corben Dallas';
        result.save(function (newResult) {
            console.log(newResult.name);    // Outputs 'Corben Dallas'
            newModel.delete(newResult.id, function (deleteResult) {
                console.log(deleteResult);  // true
            });
        });
    });

Coffeescript:

    redim = require 'redim'
    newModel = new redim.Model 'newModel',  # Model name
        ['name', 'email', 'category'],      # Model fields
        ['email']                           # Index fields, optional

    newData =
        name: 'Derek'
        email: 'derek@derekarnold.net'
        category: 'Meat Popsicle'
    newModel.create newData, (result) ->
        console.log newResult.id            # Outputs 1
        console.log result.name             # Outputs 'Derek'
        result.name = 'Corben Dallas'
        result.save (newResult) ->
            console.log newResult.name      # Outputs 'Corben Dallas'
            newModel.delete newResult.id, (deleteResult) ->
                console.log deleteResult    # true


Loading
-------

Provided are load and loadAll methods. loadAll could be fairly inefficient, so
unless you are storing some kind of enum-like representation or similar data
using a fixed number of items, don't use it.

Javascript:

    newModel.load(1, function (result) {
        console.log(result);                // Dumps the instance
    });

    newModel.loadAll(function (result) {
        console.log(result);                // Dumps a list of every instance.
    });

Coffeescript:

    newModel.load 1, (result) -> console.log result     # Dumps the instance
    newModel.loadAll (result) -> console.log result     # Dumps a list of every instance


Finding instances
-----------------

There are two methods for finding instances. Indexes are stored the same way
regardless if intended to be unique or non-unique, as lists in Redis. The only
difference is findBy returns the first item from the list and findAllBy returns
the entire list.

These examples assume more data has been created since the previous example.

Javascript:

    newModel.findBy('email', 'derek@derekarnold.net', function(result) {
        console.log(result);                // Dumps the instance matching that email address.
    });

    newModel.findAllBy('category', 'Meat Popsicle', function(result) {
        console.log(result);                // Dumps a list of matching instances
    });

Coffeescript:

    newModel.findBy 'email', 'derek@derekarnold.net', (result) ->
        console.log result                  # Dumps the instance matching that email address.

    newModel.findAllBy 'category', 'Meat Popsicle', (result) ->
        console.log result                  # Dumps a list of matching instances

Pub/Sub
-------

Using Redis' PUBLISH and SUBSCRIBE support, you can attach events to operations
on model instances (not object instances). Supported events are load, save and
delete.

Javascript:
    
    newModel.load(1, function (result) {
        result.on('save', function(instance) {
            console.log(instance.id);           // 1
            console.log(instance.name);         // 'Dumpster person'
        });
        result.category = 'Dumpster person'
        result.save(function(meaninglessResult) {});
    });

Coffeescript:
    
    newModel.load 1, (result) ->
        result.on 'save', (instance) ->
            console.log instance.id             # 1
            console.log instance.name           # 'Dumpster person'
        result.category = 'Dumpster person'
        result.save (meaninglessResult) ->


Passwords
---------

Provided for convience, a hashing shortcut. Defaults to sha1, supports anything
the crypto module supports.

Javascript:
    
    redim.hashType = 'sha1';
    console.log(redim.hash('crappypassword'));

Coffeescript:
    
    redim.hashType = 'sha1'
    console.log redim.hash 'crappypassword'


Finishing up
------------

    redim.end()

TODO
====

* Relations
* Pattern-based finds
* Integrity checks
* Wrap atomic operations in transactions
* Add single-use model instance events