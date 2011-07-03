redim = require '../lib/redim'
testCase = require('nodeunit').testCase
{forEach} = require 'async'

m = undefined

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
        callback()
    
    tearDown: (callback) ->
        redim.end()
        callback()

    newInstance: (test) ->
        test.expect 2
        m.create initData, (res) ->
            test.ok res, "Is a valid result"
            test.ok res.id, "Has a valid id"
            test.done()
    
    saveInstance: (test) ->
        test.expect 2
        newName = 'Updated Name.'
        m.create initData, (res) ->
            test.ok (res? and res.name? and res.id?), "Response is defined"
            res.name = newName
            res.save (res) ->
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
            m.create initData2, (res2) ->
                test.ok (res? and res2? and res.name? and res.id? and res2.name? and res2.id?),
                    "Response is defined"
                redim.redis.lrange 'newModel:name:Testname2', 0, 0, (err, redisRes) ->
                    test.ok redisRes? and redisRes.length > 0, "index was not saved in Redis"
                    m.findBy 'name', 'Testname2', (res3) ->
                        test.ok res3.name == res2.name, "model.findBy works"
                        m.findAllBy 'email', 'test@example.com', (res4) ->
                            test.ok res4.length > 0, "model.findAllBy failed: Only #{res4.length}"
                            test.done()

    findInstance2: (test) ->
        test.expect 2
        m.findBy 'name', 'Testname2', (res) ->
            test.ok res.name?, "Result does not have a name."
            test.ok res.name == 'Testname2', "Result does not have the correct name."
            test.done()

module.exports = testCase tests
