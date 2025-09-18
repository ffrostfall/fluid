local process = require("@lune/process")

-- stylua: ignore
process.exec(
	"rojo",
	{ "build", "--output", "fluid.rbxm" },
	{ stdio = "forward" }
)
