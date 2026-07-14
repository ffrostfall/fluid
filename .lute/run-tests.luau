local task = require("@lute/task")

local tests = require("@tests/").unit_tests

task.spawn(tests)
