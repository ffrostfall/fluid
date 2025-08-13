local process = require("@lute/process")

process.run("rojo build roblox-tests.project.json --output test-file.rbxl", { stdio = "default" })
