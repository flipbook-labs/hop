local defaultRun = require("@root/command")
local types = require("@root/types")

local function invoke(argv: { string }, runner: types.CommandRunner?)
	local run = runner or defaultRun
	local ok, result = pcall(run, argv)
	if not ok then
		error(`unable to run {argv[1]}: {result}`)
	end
	if not result.ok then
		error(`{argv[1]} failed: {result.stderr}`)
	end
end

local function open(directory: string, runner: types.CommandRunner?)
	invoke({ "code", directory }, runner)
end

local function resume(directory: string, sessionId: string, runner: types.CommandRunner?)
	invoke({ "agent", "--workspace", directory, "--resume", sessionId }, runner)
end

return table.freeze({
	open = open,
	resume = resume,
})
