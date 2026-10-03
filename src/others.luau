local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")

local snapshot = require("@root/core/snapshot")

-- Worktrees Hop checked out for other people's pull requests. Everything lives under
-- ~/.hop/cache, along with any clones made for them, so the whole directory can be deleted.
export type Store = {
	read: () -> { snapshot.Entry },
	write: ({ snapshot.Entry }) -> (),
}

local function directory(homeDirectory: path.Pathlike): path.Path
	return path.join(path.parse(tostring(homeDirectory)), ".hop", "cache")
end

local function segments(repository: string): (string, string)
	local owner, name = repository:lower():match("^([^/]+)/([^/]+)$")
	if owner == nil or name == nil then
		error(`expected owner/repo, got {repository}`, 0)
	end
	return owner, name
end

local function clonePath(homeDirectory: path.Pathlike, repository: string): path.Path
	local owner, name = segments(repository)
	return path.join(directory(homeDirectory), "repos", owner, name)
end

local function worktreePath(homeDirectory: path.Pathlike, repository: string, number: number): path.Path
	local owner, name = segments(repository)
	return path.join(directory(homeDirectory), "worktrees", owner, `{name}-pr-{number}`)
end

-- Discovery reaches these worktrees through the user's own clones, so they are filtered by location.
local function contains(homeDirectory: path.Pathlike, value: path.Pathlike): boolean
	local prefix = `{tostring(directory(homeDirectory))}/`
	return tostring(value):sub(1, #prefix) == prefix
end

-- Entries whose worktree has been deleted are dropped on read.
local function new(homeDirectory: path.Pathlike): Store
	local file = path.join(directory(homeDirectory), "others.json")
	return {
		read = function()
			if not fs.exists(file) then
				return {}
			end
			local ok, decoded = pcall(function()
				return json.deserialize(fs.readFileToString(file))
			end)
			local object = if ok then json.asObject(decoded) else nil
			local entries = if object then snapshot.entriesFromJson(object.worktrees) else nil
			local result: { snapshot.Entry } = {}
			for _, entry in entries or {} do
				if fs.exists(entry.worktree.path) then
					table.insert(result, entry)
				end
			end
			return result
		end,
		write = function(entries)
			local parent = path.dirname(file)
			if not fs.exists(parent) then
				fs.createDirectory(parent, { makeParents = true })
			end
			fs.writeStringToFile(file, json.serialize({ worktrees = snapshot.entriesToJson(entries) }))
		end,
	}
end

return table.freeze({
	clonePath = clonePath,
	contains = contains,
	new = new,
	worktreePath = worktreePath,
})
