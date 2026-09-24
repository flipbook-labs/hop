local fs = require("@std/fs")
local path = require("@std/path")

local defaultRun = require("@root/command")
local types = require("@root/types")

export type Options = {
	runner: types.CommandRunner?,
	maxDepth: number?,
	maxPrimaries: number?,
}

local SKIPPED_NAMES: { [string]: boolean } = {
	Library = true,
	Applications = true,
	Pictures = true,
	Movies = true,
	Music = true,
	[".Trash"] = true,
	node_modules = true,
	[".cache"] = true,
	[".npm"] = true,
	[".local"] = true,
}

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$") or ""
end

local function repositoryFromRemote(remote: string): string?
	local repository = remote:match("^git@github%.com:(.+)$")
		or remote:match("^https?://github%.com/(.+)$")
		or remote:match("^ssh://git@github%.com/(.+)$")
	if repository == nil then
		return nil
	end
	repository = repository:gsub("%.git$", "")
	return if repository:match("^[%w%._%-]+/[%w%._%-]+$") then repository else nil
end

local function commandOutput(runner: types.CommandRunner, argv: { string }): string?
	local ok, result = pcall(runner, argv)
	if not ok or not result.ok then
		return nil
	end
	return trim(result.stdout)
end

local function parseWorktreeList(
	contents: string,
	repository: string?,
	primaryPath: string,
	defaultBranch: string?
): { types.Worktree }
	local result: { types.Worktree } = {}
	local current: types.Worktree? = nil
	for line in (contents .. "\n"):gmatch("(.-)\r?\n") do
		local worktreePath = line:match("^worktree (.+)$")
		if worktreePath then
			if current then
				table.insert(result, current)
			end
			local created: types.Worktree = {
				path = path.parse(worktreePath),
				branch = nil,
				repository = repository,
				root = primaryPath,
				head = nil,
				defaultBranch = defaultBranch,
				primary = worktreePath == primaryPath,
			}
			current = created
		elseif current then
			local branch = line:match("^branch refs/heads/(.+)$")
			local head = line:match("^HEAD (%x+)$")
			if branch then
				current.branch = branch
			elseif head then
				current.head = head
			end
		end
	end
	if current then
		table.insert(result, current)
	end
	return result
end

local function discover(roots: { path.Path }, options: Options?): { types.Worktree }
	local resolved: Options = options or {}
	local maxDepth = resolved.maxDepth or 4
	local maxPrimaries = resolved.maxPrimaries or 200
	local runner = resolved.runner or defaultRun
	local primaries: { path.Path } = {}

	local function visit(directory: path.Path, depth: number)
		if #primaries >= maxPrimaries or depth > maxDepth or not fs.exists(directory) then
			return
		end
		local okType, directoryType = pcall(fs.type, directory)
		if not okType or directoryType ~= "dir" then
			return
		end

		local gitPath = path.join(directory, ".git")
		if fs.exists(gitPath) then
			local gitTypeOk, gitType = pcall(fs.type, gitPath)
			if gitTypeOk and gitType == "dir" then
				table.insert(primaries, directory)
			end
			return
		end

		local ok, entries = pcall(fs.listDirectory, directory)
		if not ok then
			return
		end
		local sorted = entries :: { fs.DirectoryEntry }
		table.sort(sorted, function(left: fs.DirectoryEntry, right: fs.DirectoryEntry)
			return left.name < right.name
		end)
		for _, entry in sorted do
			if #primaries >= maxPrimaries then
				break
			end
			if entry.type == "dir" and not SKIPPED_NAMES[entry.name] then
				visit(path.join(directory, entry.name), depth + 1)
			end
		end
	end

	for _, root in roots do
		if #primaries >= maxPrimaries then
			break
		end
		visit(path.parse(tostring(root)), 0)
	end

	local result: { types.Worktree } = {}
	local seen: { [string]: boolean } = {}
	for _, primary in primaries do
		local primaryString = tostring(primary)
		local remote = commandOutput(runner, { "git", "-C", primaryString, "remote", "get-url", "origin" })
		local repository = if remote then repositoryFromRemote(remote) else nil
		local originHead = commandOutput(
			runner,
			{ "git", "-C", primaryString, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }
		)
		local defaultBranch = if originHead then originHead:match("^[^/]+/(.+)$") else nil
		local porcelain = commandOutput(runner, { "git", "-C", primaryString, "worktree", "list", "--porcelain" })
		if porcelain then
			for _, worktree in parseWorktreeList(porcelain, repository, primaryString, defaultBranch) do
				local key = tostring(worktree.path)
				if not seen[key] then
					seen[key] = true
					table.insert(result, worktree)
				end
			end
		end
	end
	table.sort(result, function(left, right)
		return tostring(left.path) < tostring(right.path)
	end)
	return result
end

local function gitDirectory(worktree: types.Worktree): path.Path?
	local dotGit = path.join(worktree.path, ".git")
	local okType, kind = pcall(fs.type, dotGit)
	if not okType then
		return nil
	elseif kind == "dir" then
		return dotGit
	elseif kind ~= "file" then
		return nil
	end
	local okRead, contents = pcall(fs.readFileToString, dotGit)
	local target = if okRead then contents:match("^gitdir:%s*(.-)%s*$") else nil
	if target == nil or target == "" then
		return nil
	end
	return if path.isAbsolute(target) then path.parse(target) else path.join(worktree.path, target)
end

-- Seconds since the epoch that the worktree's index last changed, or 0 when unknown.
-- Git rewrites the index on checkout, commit, and status refreshes, so it tracks recent use.
local function lastActivity(worktree: types.Worktree): number
	local directory = gitDirectory(worktree)
	if directory == nil then
		return 0
	end
	local ok, metadata = pcall(fs.metadata, path.join(directory, "index"))
	return if ok then metadata.modified:toSeconds() else 0
end

return table.freeze({
	discover = discover,
	lastActivity = lastActivity,
	parseWorktreeList = parseWorktreeList,
	repositoryFromRemote = repositoryFromRemote,
})
