local process = require("@std/process")

local types = require("@root/types")

local function run(argv: { string }): types.CommandResult
	local result = process.run(argv)
	return {
		ok = result.ok,
		exitCode = result.exitcode,
		stdout = result.stdout,
		stderr = result.stderr,
	}
end

return run
