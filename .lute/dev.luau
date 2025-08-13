local process = require("@lute/process")
local task = require("@lute/task")

task.spawn(function()
	process.run(
		"rojo sourcemap roblox-tests.project.json --output sourcemap.json --watch --include-non-scripts",
		{
			stdio = "default",
		}
	)
end)

task.spawn(function()
	process.run("rojo serve roblox-tests.project.json", { stdio = "default" })
end)
