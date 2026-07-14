local process = require("@lute/process")

local cmd = { "stylua", ".lute", "src", "tests" }

-- kinda cursed but, easiest way to do this.
table.insert(cmd, "--check")

local result = process.run(cmd, {
	stdio = "inherit",
})

process.exit(result.exitcode)
