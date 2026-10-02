local defaultRun = require("@root/command")
local types = require("@root/types")

local EXTENSION_ID = "flipbook-labs.hop"

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

-- Asks VS Code rather than inspecting its extensions folder, which can keep uninstalled
-- extensions until VS Code cleans up. VS Code's CLI cannot report whether an extension is disabled.
local function extensionInstalled(runner: types.CommandRunner?): boolean
	local run = runner or defaultRun
	local ok, result = pcall(run, { "code", "--list-extensions" })
	if not ok or not result.ok then
		return false
	end
	for line in result.stdout:gmatch("[^\r\n]+") do
		if line:lower() == EXTENSION_ID then
			return true
		end
	end
	return false
end

local function encode(value: string): string
	return (value:gsub("[^%w%-%._~/]", function(character)
		return string.format("%%%02X", character:byte())
	end))
end

local function handoffUri(directory: string): string
	return `vscode://flipbook-labs.hop/to?path={encode(directory)}`
end

-- With the Hop extension installed, the most recently focused VS Code window switches to
-- the folder in place. Otherwise VS Code opens it the usual way.
local function open(directory: string, runner: types.CommandRunner?)
	if extensionInstalled(runner) then
		invoke({ "open", handoffUri(directory) }, runner)
		return
	end
	invoke({ "code", directory }, runner)
end

local function resume(directory: string, sessionId: string, runner: types.CommandRunner?)
	invoke({ "agent", "--workspace", directory, "--resume", sessionId }, runner)
end

return table.freeze({
	handoffUri = handoffUri,
	open = open,
	resume = resume,
})
