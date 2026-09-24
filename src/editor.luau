local fs = require("@std/fs")
local path = require("@std/path")

local defaultRun = require("@root/command")
local types = require("@root/types")

local EXTENSION_PREFIX = "flipbook-labs.hop-"

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

local function extensionInstalled(homeDirectory: string): boolean
	local ok, entries = pcall(fs.listDirectory, path.join(homeDirectory, ".vscode", "extensions"))
	if not ok then
		return false
	end
	for _, entry in entries :: { fs.DirectoryEntry } do
		if entry.name:sub(1, #EXTENSION_PREFIX) == EXTENSION_PREFIX then
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
local function open(directory: string, runner: types.CommandRunner?, homeDirectory: string?)
	if homeDirectory and extensionInstalled(homeDirectory) then
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
