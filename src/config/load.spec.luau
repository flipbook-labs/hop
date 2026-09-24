local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local test = require("@std/test")

local load = require("@root/config/load")

local function temporaryDirectory(name: string): path.Path
	local directory = path.join(system.tmpdir(), `hop-config-{process.pid()}-{name}`)
	if fs.exists(directory) then
		fs.removeDirectory(directory, { recursive = true })
	end
	fs.createDirectory(directory, { makeParents = true })
	return directory
end

test.case("config defaults roots to the home directory", function(assert)
	local home = temporaryDirectory("missing")
	local config = load({ homeDirectory = home })
	assert.eq(tostring(config.roots[1]), tostring(home))
	assert.eq(#config.roots, 1)
end)

test.case("config loads roots with luau.loadModule", function(assert)
	local home = temporaryDirectory("custom")
	local configPath = path.join(home, "config.luau")
	fs.writeStringToFile(configPath, 'return { roots = { "/one", "/two" } }\n')
	local config = load({ homeDirectory = home, configPath = configPath })
	assert.eq(tostring(config.roots[1]), "/one")
	assert.eq(tostring(config.roots[2]), "/two")
end)

test.case("config rejects a module that does not return a table", function(assert)
	local home = temporaryDirectory("invalid")
	local configPath = path.join(home, "config.luau")
	fs.writeStringToFile(configPath, 'return "invalid"\n')
	local ok, message = pcall(function()
		return load({ homeDirectory = tostring(home), configPath = tostring(configPath) })
	end)
	assert.eq(ok, false)
	assert.strContains(tostring(message), "must return a table")
end)
