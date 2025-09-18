local process = require("@lune/process")
local task = require("@lune/task")

task.spawn(function()
	process.exec("rojo", {
		"sourcemap",
		"roblox-tests.project.json",
		"--output",
		"sourcemap.json",
		"--watch",
		"--include-non-scripts",
	}, {
		stdio = "forward",
	})
end)

task.spawn(function()
	-- stylua: ignore
	process.exec(
		"rojo",
		{ "serve", "roblox-tests.project.json" },
		{ stdio = "forward" }
	)
end)
