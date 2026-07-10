local process = require("@lune/process")

local directories = { ".lune", "src", "tests" }

-- kinda cursed but, easiest way to do this.
table.insert(directories, "--check")

local result = process.exec("stylua", directories, {
	stdio = "forward",
})

process.exit(result.code)
