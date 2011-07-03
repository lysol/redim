crypto = require 'crypto'
redisModule = require 'redis'
util = require 'util'
salt = ""
hashType = 'sha1'
{forEach} = require 'async'
redis = undefined
subscriber = undefined
connectTuple = undefined

# This is the list of callbacks for various pub/sub channels
subListeners = {}
subscribed = false

# We keep track of what models have been created, so when an instance is passed
# from the server, we know which one to tie it to and attach the appropriate methods
modelRegistry = {}

handleSubMessage = (channel, message) ->
    newInstance = JSON.parse message
    for key, cbList of subListeners
        if key == channel
            for cb in cbList
                if newInstance.id? and newInstance._model? and modelRegistry[newInstance._model.name]?
                    # It's an instance
                    model = modelRegistry[newInstance._model.name]
                    model.attachSave newInstance
                    model.attachOn newInstance
                    cb newInstance
            return

emitSubMessage = (event, instance) ->
    channel = "#{instance._model.name}:#{instance.id}:#{event}"
    redis.publish channel, JSON.stringify instance

setOn = (channel, callback) ->
    if not subscribed
        subscriber.on "message", handleSubMessage
    if not subListeners[channel]?
        subListeners[channel] = []
    subListeners[channel].push callback
    subscriber.subscribe channel
    return subListeners[channel].length - 1

hash = (text) ->
    ((crypto.createHash hashType).update text + salt).digest 'hex'

createClient = (port, host, options) =>
    connectTuple = [port, host, options]
    module.exports.redis = redisModule.createClient port, host, options
    subscriber = redisModule.createClient port, host, options
    redis = module.exports.redis
auth = (password, callback) ->
    subscriber.auth password, callback, () ->
        redis.auth password, callback
end = () => redis.end()

class Model
    ###
    constructor

    @name: The name that will be used as the first token of all keys
    @fields: The main fields that will be used for storage.
    @indexFields: You must include any fields you will be using to perform lookups.
    ###
    constructor: (@name, @fields, @indexFields=[]) ->
        # set the id increment field
        redis.get "#{@name}:id", (err, data) =>
            redis.set "#{@name}:id", 1 if err?
            modelRegistry[@name] = @
    parent = @

    ###
    delete method
    
    id: The id of the instance you are going to destroy.
    callback: Called with either the error returned by Redis or a true value
              for a successful deletion.
    ###
    delete: (id, callback) ->
        i = 0
        @load id, (origInstance) =>
            prefix = "#{@name}:#{id}:"

            rcall = (field, nextField) =>
                passBack = () ->
                    redis.del prefix + field, (err) ->
                        if err?
                            throw err
                        else
                            nextField()
                if field in @indexFields
                    @reIndex field, (res) ->
                        if res? and res
                            passBack()
                        else
                            throw "Reindexing failed."
                else
                    passBack()

            forEach @fields, rcall, (err) =>
                if err?
                    throw err
                else
                    emitSubMessage 'delete', origInstance
                    callback true
    
    ###
    load method
    
    id: The id of the instance you are loading.
    callback: Called with either an instance of the object you are loading
              or the error returned by Redis.
    ###
    
    load: (id, callback) ->
        robj =
            "id": id
        prefix = "#{@name}:#{id}:"

        rcall = (field, nextField) =>
            redis.get "#{prefix}#{field}", (err, data) =>
                if err?
                    throw err
                else
                    robj[field] = data
                nextField()

        forEach @fields, rcall, (err) =>
            if err?
                throw err
            else
                @attachSave robj
                @attachOn robj
                robj._model = @
                emitSubMessage 'load', robj
                callback robj
    
    ###
    findAllBy method
    Returns all object instances with a specific value in a specific field.
    
    field: Name of the field being queried.
    value: The specific value to find.
    callback: Called either with list of instances or a null response.
    ###
    findAllBy: (field, value, callback) ->
        if @indexFields.indexOf field > -1
            redis.lrange "#{@name}:#{field}:#{value}", 0, -1, (err, data) =>
                if err?
                    throw err
                    callback null
                if err? or not data?
                    callback null
                    return
                instances = []
                i = 0
                icb = (instance) =>
                    if instance?
                        instances.push instance
                        i++
                    if i < data.length
                        @load data[i], icb
                    else
                        callback instances
                icb()

    ###
    findBy method
    Returns the first object instance  with a specific value in a specific field.
    Intended for unique values, but not enforced.

    field: Name of the field being queried.
    value: The specific value to find.
    callback: Called eitehr with the instance or a null response.
    ###
    findBy: (field, value, callback) ->
        if field in @indexFields
            # do stuff
            redis.lrange "#{@name}:#{field}:#{value}", 0, 0, (err, data) =>
                if err?
                    throw err
                    callback err
                if not data?
                    callback null
                else
                    @load data[0], (instance) -> callback instance
        else
            throw "Attempting to find using an unindexed field."

    ###
    loadAll method
    Loads every instance of this model.

    callback: Is called with either the list of instances or the error
              Redis returns.
    ###
    loadAll: (callback) ->
        i = 1
        maxI = -1
        prefix = "#{@name}:id"
        robjs = []
        rcall = (data) =>
            robjs.push data if data?
            i++
            if i < maxI
                @load i, rcall
            else
                callback robjs

        redis.get prefix, (err, data) =>
            if not err? and data?
                maxI = data
                @load 1, rcall
            else
                callback err

    ###
    attachOn method
    Sets up the on method on instances.
    instance: the thing
    ###
    attachOn: (instance) ->

        buildChannel = (eventName) =>
            "#{@name}:#{instance.id}:#{eventName}"

        instance.on = (eventName, callback) =>
            channel = buildChannel(eventName)
            setOn channel, callback
        
        instance.removeListener = (eventName, index) =>
            channel = buildChannel(eventName)
            try
                # gross, but this way the indexes still work
                # if they remove another one later.
                subListeners[channel][index] = () ->
            catch err
                throw "Could not remove listener: #{channel} #{index}"
        
        instance.removeListeners = (eventName) =>
            channel = buildChannel(eventName)
            try
                subListeners[channel] = []
            catch err
                throw "No listeners were defined: #{channel}"

    ###
    attachSave method
    Used by parts of the model that build instances to add a save method.
    This should not be used directly.
    instance: guess
    ###
    attachSave: (instance) ->
        save = (callback) =>
            prefix = "#{@name}:#{instance.id}:"
            numFields = @fields.length
            rcall = (field, nextField) =>
                redis.set prefix + field, instance[field], (err) =>
                    if err?
                        throw err
                    else
                        if field in @indexFields
                            @reIndex field, (res) ->
                                if res? and res
                                    nextField()
                                else
                                    throw "Reindex failed"
                        else
                            nextField()
            forEach @fields, rcall, (err) =>
                if err?
                    throw err
                else
                    emitSubMessage 'save', instance
                    callback instance

        instance.save = save

    ###
    create method

    Creates a new instance and saves it in Redis right away.
    data: The data, minus the id that goes into the model's fields.
    callback: Is called either with either the new instance or the error
              Redis returns.
    ###
    create: (data, callback) ->
        newData = {}
        for key, val of data
            if key in @fields
                newData[key] = val
        redis.incr "#{@name}:id", (err, id) =>
            if not err?
                newData.id = id
                @attachSave newData
                @attachOn newData
                newData._model = @
                newData.save (res) =>
                    callback res
            else
                throw err

    ###
    reIndex method

    Rewrites an entire index from scratch. 
    ###
    reIndex: (field, callback) ->
        indexKey = "#{@name}:#{field}"
        redis.keys "#{indexKey}:*", (err, iKeys) =>
            if err?
                throw err
            else
                deleter = (key, fcallback2) =>
                    redis.del key, (err) =>
                        if err?
                            throw err
                        fcallback2()
                passBack = () =>
                    redis.keys "#{@name}:*:#{field}", (err, keys) =>
                        indexer = (key, lcallback) =>
                            tokens = key.split ':'
                            id = tokens[1]
                            redis.get key, (err, data) =>
                                if not err? and data
                                    redis.lpush "#{indexKey}:#{data}", id, (err) =>
                                        if err?
                                            throw err
                                        lcallback()
                                else if err?
                                    throw err
                                    lcallback()
                        forEach keys, indexer, (err) =>
                            if err?
                                throw err
                                callback false
                            else
                                callback true
                if iKeys.length > 0
                    forEach iKeys, deleter, (err) =>
                        if err?
                            throw err
                        passBack()
                else
                    passBack()

    ###
    reIndexAll method

    Rewrites all indexes from scratch.
    ###
    reIndexAll: (callback) ->
        indexer = (field, fcallback) =>
            @reIndex field, (res) =>
                fcallback()
        forEach @indexFields, indexer, (err) ->
            if err
                throw err
            else
                callback true

module.exports.hashType = hashType
module.exports.hash = hash
module.exports.salt = salt
module.exports.createClient = createClient
module.exports.end = end
module.exports.Model = Model
module.exports.redis = redis
