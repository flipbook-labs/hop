local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")

local snapshot = require("@root/core/snapshot")

export type Cache = {
	read: () -> snapshot.Snapshot?,
	write: (snapshot.Snapshot) -> (),
}

local function cachePath(homeDirectory: path.Pathlike): path.Path
	return path.join(path.parse(tostring(homeDirectory)), ".hop", "cache", "worktrees.json")
end

-- A missing or unreadable cache is treated as absent so Hop can rebuild it.
local function new(homeDirectory: path.Pathlike): Cache
	local file = cachePath(homeDirectory)
	return {
		read = function()
			if not fs.exists(file) then
				return nil
			end
			local ok, decoded = pcall(function()
				return json.deserialize(fs.readFileToString(file))
			end)
			return if ok then snapshot.fromJson(decoded) else nil
		end,
		write = function(value)
			local directory = path.dirname(file)
			if not fs.exists(directory) then
				fs.createDirectory(directory, { makeParents = true })
			end
			fs.writeStringToFile(file, json.serialize(snapshot.toJson(value)))
		end,
	}
end

return table.freeze({
	cachePath = cachePath,
	new = new,
})
