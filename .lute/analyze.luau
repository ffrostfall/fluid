local fs = require("@lute/fs")
local net = require("@lute/net/client")
local process = require("@lute/process")

if fs.type("types/globalTypes.d.luau") ~= "file" then
	local response = net.request(
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/refs/heads/main/scripts/globalTypes.d.luau"
	)

	assert(response.ok, response.headers.statusMessage)

	local handle = fs.open("types/globalTypes.d.luau", "w+")
	fs.write(handle, response.body)
	fs.close(handle)
end

local status = process.run({
	"luaulsp",
	"analyze",
	"--definitions=types/globalTypes.d.luau",
	"--base-luaurc=.luaurc",
	"--flag:LuauSolverV2=true",
	"src",
}, {
	stdio = "inherit",
})

process.exit(status.exitcode)
