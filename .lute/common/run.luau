local process = require("@std/process")

export type Options = {
	capture: boolean?,
	cwd: string?,
}

local function run(arguments: { string }, options: Options?)
	local resolved: Options = options or {}
	local result = process.run(arguments, {
		cwd = resolved.cwd,
		stdio = if resolved.capture then "default" else "inherit",
	})
	if not result.ok then
		error(`command failed ({result.exitcode}): {table.concat(arguments, " ")}\n{result.stderr}`)
	end
	return result
end

return run
