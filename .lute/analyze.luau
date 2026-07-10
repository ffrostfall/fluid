local fs = require("@lute/fs")
local net = require("@lute/net")
local process = require("@lute/process")

if not fs.isFile("types/globalTypes.d.luau") then
	local response = net.request(
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/refs/heads/main/scripts/globalTypes.d.luau"
	)

	assert(response.ok, response.statusMessage)

	fs.writeFile("types/globalTypes.d.luau", response.body)
end

local status = process.exec("luaulsp", {
	"analyze",
	"--definitions=types/globalTypes.d.luau",
	"--base-luaurc=.luaurc",
	"--flag:LuauSolverV2=true",
	"src",
}, {
	stdio = "forward",
})

process.exit(status.code)
