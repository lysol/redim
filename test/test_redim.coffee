redim = require '../lib/redim'
testCase = require('nodeunit').testCase
{forEach} = require 'async'

m = undefined
collectedInstances = []

initData =
    name: 'Testname'
    email: 'test@example.com'
    category: 'Dogs'


tests =
    setUp: (callback) ->
        redim.createClient()
        redim.salt = "This is a test salt."
        m = new redim.Model 'newModel',
            ['name', 'email', 'category'],
            ['name', 'email']
        collectedInstances = []
        callback()
    
    tearDown: (callback) ->
        dins = (ins, nextIns) ->
            m.delete ins.id, (res) ->
                nextIns()
        forEach collectedInstances, dins, (err) ->
            if err?
                throw err
            else
                redim.redis.del "newModel:id", (err) ->
                    if err?
                        throw err
                    redim.end()
                    callback()

    newInstance: (test) ->
        test.expect 2
        m.create initData, (res) ->
            test.ok res, "Is a valid result"
            test.ok res.id, "Has a valid id"
            collectedInstances.push res
            test.done()
    
    saveInstance: (test) ->
        test.expect 2
        newName = 'Updated Name.'
        m.create initData, (res) ->
            test.ok (res? and res.name? and res.id?), "Response is defined"
            res.name = newName
            res.save (res) ->
                collectedInstances.push res
                test.equal res.name, newName, "Name update works"
                test.done()
    
    deleteInstance: (test) ->
        test.expect 2
        m.create initData, (res) ->
            test.ok (res? and res.name? and res.id?), "Response is defined"
            m.delete res.id, (res2) ->
                test.ok (res2? and res2 == true), "Was successfully deleted."
                test.done()

    findInstance: (test) ->
        
        m.create initData, (res) ->
            test.expect 4
            initData2 = initData
            initData2.name = 'Testname2'
            collectedInstances.push res
            m.create initData2, (res2) ->
                collectedInstances.push res2
                test.ok (res? and res2? and res.name? and res.id? and res2.name? and res2.id?),
                    "Response is defined"
                redim.redis.lrange 'newModel:name:Testname2', 0, 0, (err, redisRes) ->
                    test.ok redisRes? and redisRes.length > 0, "index was not saved in Redis"
                    redim.redis.keys "newModel:#{redisRes[0]}:*", (err, data) ->
                        redim.redis.get "newModel:#{redisRes[0]}:name", (err, data) ->
                            m.findBy 'name', 'Testname2', (res3) ->
                                test.ok res3.name == res2.name, "model.findBy didn't work"
                                m.findAllBy 'email', 'test@example.com', (res4) ->
                                    test.ok res4.length > 0, "model.findAllBy failed: Only #{res4.length}"
                                    test.done()

    testSubscriptions: (test) ->
        test.expect 2
        instanceWork = undefined
        m.create initData, (res) ->
            res.name = 'Gomer Pyle'
            saveId = res.on 'save', (instance) ->
                console.log ">>> Running instance name test"
                test.ok instance.name == res.name,
                    "Name did not match the version before the save."
                delId = instance.on 'delete', (instance2) ->
                    console.log ">>> Running second instance name test"
                    test.ok instance2.name == instance.name,
                        "Name did not match the version before deletion."
                    instance.removeListener 'delete', delId
                    instance.removeListeners 'delete'
                    test.done()
                m.delete instance.id, (res3) ->
                    console.log "If you get stuck here, the delete event did not work."
            res.save (res2) ->
                console.log "Received saveId: #{saveId}"
                console.log "If you get stuck here, the save event did not work."
    

module.exports = testCase tests
