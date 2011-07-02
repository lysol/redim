redim = require '../lib/redim'
testCase = require('nodeunit').testCase

m = undefined

initData =
    name: 'Testname'
    email: 'test@example.com'
    category: 'Dogs'


tests =
    setUp: (callback) ->
        redim.start()
        redim.salt = "This is a test salt."
        m = new redim.Model 'newModel',
            ['name', 'email', 'category'],
            ['name', 'email']
        callback()
    
    tearDown: (callback) ->
        redim.stop()
        callback()

    newInstance: (test) ->
        test.expect 2
        m.create initData, (res) ->
            console.log 'create callback result'
            test.ok res, "Is a valid result"
            test.ok res.id, "Has a valid id"
            test.done()
    
    saveInstance: (test) ->
        test.expect 2
        newName = 'Updated Name.'
        console.log m
        
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

module.exports = testCase tests
