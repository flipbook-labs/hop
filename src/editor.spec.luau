local test = require("@std/test")

local editor = require("@root/editor")
local types = require("@root/types")

local function fakeCode(extensions: string, commands: { { string } }): types.CommandRunner
	return function(argv)
		table.insert(commands, argv)
		if argv[1] == "code" and argv[2] == "--list-extensions" then
			return { ok = true, exitCode = 0, stdout = extensions, stderr = "" }
		end
		return { ok = true, exitCode = 0, stdout = "", stderr = "" }
	end
end

test.case("editor hands off to the Hop extension when VS Code lists it", function(assert)
	local commands: { { string } } = {}
	editor.open("/src/my widgets", fakeCode("ms-python.python\nFlipbook-Labs.hop\n", commands))
	local last = commands[#commands]
	assert.eq(last[1], "open")
	assert.eq(last[2], "vscode://flipbook-labs.hop/to?path=/src/my%20widgets")
end)

test.case("editor falls back to code without the extension", function(assert)
	local commands: { { string } } = {}
	editor.open("/src/widgets", fakeCode("flipbook-labs.hop-other\n", commands))
	local last = commands[#commands]
	assert.eq(last[1], "code")
	assert.eq(last[2], "/src/widgets")
end)

test.case("editor falls back to code when VS Code cannot list extensions", function(assert)
	local commands: { { string } } = {}
	editor.open("/src/widgets", function(argv)
		table.insert(commands, argv)
		local listing = argv[2] == "--list-extensions"
		return { ok = not listing, exitCode = if listing then 1 else 0, stdout = "", stderr = "" }
	end)
	local last = commands[#commands]
	assert.eq(last[1], "code")
	assert.eq(last[2], "/src/widgets")
end)
