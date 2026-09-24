local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local test = require("@std/test")

local editor = require("@root/editor")

local function home(name: string, installed: boolean): string
	local directory = path.join(system.tmpdir(), `hop-editor-{process.pid()}-{name}`)
	if fs.exists(directory) then
		fs.removeDirectory(directory, { recursive = true })
	end
	local extensions = path.join(directory, ".vscode", "extensions")
	fs.createDirectory(extensions, { makeParents = true })
	if installed then
		fs.createDirectory(path.join(extensions, "flipbook-labs.hop-0.0.0-darwin-arm64"))
	end
	return tostring(directory)
end

test.case("editor hands off to the Hop extension when it is installed", function(assert)
	local command: { string } = {}
	editor.open("/src/my widgets", function(argv)
		command = argv
		return { ok = true, exitCode = 0, stdout = "", stderr = "" }
	end, home("installed", true))
	assert.eq(command[1], "open")
	assert.eq(command[2], "vscode://flipbook-labs.hop/to?path=/src/my%20widgets")
end)

test.case("editor falls back to code without the extension", function(assert)
	local command: { string } = {}
	editor.open("/src/widgets", function(argv)
		command = argv
		return { ok = true, exitCode = 0, stdout = "", stderr = "" }
	end, home("missing", false))
	assert.eq(command[1], "code")
	assert.eq(command[2], "/src/widgets")
end)
