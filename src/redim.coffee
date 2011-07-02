crypto = require 'crypto'
redisModule = require 'redis'
redis = undefined
util = require 'util'
salt = ""
hashType = 'sha1'

hash = (text) ->
    ((crypto.createHash hashType).update text + salt).digest 'hex'

createClient = (port, host, options) ->
    redis = redisModule.createClient port, host, options
auth = (password, callback) -> client.auth password, callback
end = () -> redis.end()

class Model
    ###
    constructor

    @modelName: The name that will be used as the first token of all keys
    @fields: The main fields that will be used for storage.
    @indexFields: You must include any fields you will be using to perform lookups.
    ###
    constructor: (@modelName, @fields, @indexFields=[]) ->
        # set the id increment field

        redis.get "#{@modelName}:id", (err, data) ->
            redis.set "#{@modelName}:id", 1 if err?
    parent = @

    ###
    delete method
    
    id: The id of the instance you are going to destroy.
    callback: Called with either the error returned by Redis or a true value
              for a successful deletion.
    ###
    delete: (id, callback) ->
        i = 0
        prefix = "#{@modelName}:#{id}:"
        rcall = (err) =>
            if err?
                console.log "Error at delete: #{err}"
                callback err
                return

            if i < @fields.length
                # if indexed, remove this ID from the index.
                if @indexFields.indexOf(@fields[i]) + 1
                    redis.get prefix + @fields[i], (err, data) =>
                        if not err? and data?
                            redis.lrem "#{@modelName}:#{@fields[i]}:#{data}", 1, id
                i++
                redis.del prefix + @fields[i - 1], rcall
            else
                callback true
        rcall()
    
    ###
    load method
    
    id: The id of the instance you are loading.
    callback: Called with either an instance of the object you are loading
              or the error returned by Redis.
    ###
    load: (id, callback) ->
        i = -1
        prefix = "#{@modelName}:#{id}:"
        robj =
            "id": id
        rcall = (err, data) =>
            i++
            if err?
                console.log "Error at load: #{err}"
                callback err
                return
            else
                if i < @fields.length
                    curfield = @fields[i]
                    robj[curfield] = data
                    redis.get prefix + @fields[i + 1], rcall
                else
                    attachSave robj
                    callback robj
        redis.get prefix + @fields[0], rcall

    ###
    findAllBy method
    Returns all object instances with a specific value in a specific field.
    
    field: Name of the field being queried.
    value: The specific value to find.
    callback: Called either with list of instances or a null response.
    ###
    findAllBy: (field, value, callback) ->
        if @indexFields.indexOf field > -1
            redis.lrange "#{@modelName}:#{field}:#{value}", 0, -1, (err, data) =>
                if err?
                    console.log err
                if err? or not data?
                    callback null
                    return
                instances = []
                i = 0
                icb = (instance) ->
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
        if @indexFields.indexOf field > -1
            # do stuff
            redis.lrange "#{@modelName}:#{field}:#{value}", 0, 1, (err, data) =>
                if err?
                    console.log err
                if err? or not data?
                    callback null
                    return
                if data.length == 1
                    @load data[0], (instance) -> callback instance
                else
                    callback null
        else
            callback null

    ###
    loadAll method
    Loads every instance of this model.

    callback: Is called with either the list of instances or the error
              Redis returns.
    ###
    loadAll: (callback) ->
        i = 1
        maxI = -1
        prefix = "#{@modelName}:id"
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
    attachSave method
    Used by parts of the model that build instances to add a save method.
    This should not be used directly.
    instance: guess
    ###
    attachSave: (instance) ->
        save = (callback) =>
            i = 0
            prefix = "#{@modelName}:#{instance.id}:"
            numFields = @fields.length
            rcall = (err) =>
                if err?
                    callback err
                else if i < numFields
                    curField = @fields[i]
                    i++
                    redis.set prefix + @fields[i - 1], instance[curField], rcall
                else
                    callback instance
            rcall()
        instance.save = save

    ###
    create method

    Creates a new instance and saves it in Redis right away.
    data: The data, minus the id that goes into the model's fields.
    callback: Is called either with either the new instance or the error
              Redis returns.
    ###
    create: (data, callback) ->
        redis.incr "#{@modelName}:id", (err, id) =>
            if not err?
                data.id = id
                @attachSave data
                data.save (res) =>
                    callback res
            else
                console.log "Error at create: #{err}"
                callback err

module.exports.hashType = hashType
module.exports.hash = hash
module.exports.salt = salt
module.exports.createClient = createClient
module.exports.end = end
module.exports.Model = Model
module.exports.redis = redis
