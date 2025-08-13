local process = require("@lute/process")

local directories = { ".lune", "src", "tests" }

-- kinda cursed but, easiest way to do this.
table.insert(directories, "--check")

local result = process.run("stylua " .. table.concat(directories, " "), {
	stdio = "default",
})

process.exit(result.exitcode)
