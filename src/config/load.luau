local fs = require("@std/fs")
local luau = require("@std/luau")
local path = require("@std/path")
local process = require("@std/process")

export type Config = {
	roots: { path.Path },
}

export type Options = {
	homeDirectory: path.Pathlike?,
	configPath: path.Pathlike?,
}

local function load(options: Options?): Config
	local resolved: Options = options or {}
	local home = path.parse(tostring(resolved.homeDirectory or process.homedir()))
	local configPath = resolved.configPath or path.join(home, ".hop", "config.luau")
	if not fs.exists(configPath) then
		return { roots = { home } }
	end

	local ok, value = pcall(luau.loadModule, configPath, nil)
	if not ok then
		error(`failed to load {configPath}: {value}`)
	end
	if type(value) ~= "table" then
		error(`{configPath} must return a table`)
	end

	local rootsValue: unknown = (value :: { [string]: unknown }).roots
	if rootsValue == nil then
		return { roots = { home } }
	end
	if type(rootsValue) ~= "table" then
		error(`{configPath} roots must be an array of paths`)
	end

	local roots: { path.Path } = {}
	for index, root in rootsValue :: { unknown } do
		if type(root) ~= "string" or root == "" then
			error(`{configPath} roots[{index}] must be a non-empty string`)
		end
		table.insert(roots, path.parse(root))
	end
	return { roots = roots }
end

return load
