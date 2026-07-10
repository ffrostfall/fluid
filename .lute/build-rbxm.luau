local process = require("@lute/process")

-- stylua: ignore
process.run(
	"rojo",
	{ "build", "--output", "fluid.rbxm" },
	{ stdio = "forward" }
)
