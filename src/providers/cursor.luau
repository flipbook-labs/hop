local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")
local process = require("@std/process")

local defaultRun = require("@root/command")
local providers = require("@root/providers")
local types = require("@root/types")

export type Options = {
	homeDirectory: path.Pathlike?,
	databasePath: path.Pathlike?,
	workspaceStoragePath: path.Pathlike?,
	runner: types.CommandRunner?,
}

local Cursor = {}

local function decodeUri(value: string): string
	local result = value:match("^file://localhost(/.*)$") or value:match("^file://(/.*)$") or value
	local decoded = result:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16) :: number)
	end)
	return decoded
end

local function workspaceDirectory(storage: path.Pathlike, workspaceId: string): string?
	local metadataPath = path.join(storage, workspaceId, "workspace.json")
	if not fs.exists(metadataPath) then
		return nil
	end
	local readOk, contents = pcall(fs.readFileToString, metadataPath)
	if not readOk then
		return nil
	end
	local decodeOk, decoded = pcall(json.deserialize, contents)
	local object = if decodeOk then json.asObject(decoded) else nil
	local raw = if object then object.folder or object.workspace else nil
	return if type(raw) == "string" then decodeUri(raw) else nil
end

local function trackedContext(header: json.Object, workspaceDirectory: string?): (string?, string?)
	local repositories = json.asArray(header.trackedGitRepos)
	if not repositories then
		return workspaceDirectory, nil
	end
	local selectedDirectory: string? = nil
	local selectedBranch: string? = nil
	local selectedAt = -math.huge
	for _, repositoryValue in repositories do
		local repository = json.asObject(repositoryValue)
		local repoPath = if repository then repository.repoPath else nil
		local branches = if repository then json.asArray(repository.branches) else nil
		if branches then
			for _, branchValue in branches do
				local branch = json.asObject(branchValue)
				local name = if branch then branch.branchName else nil
				local interactedAt = if branch then branch.lastInteractionAt else nil
				local timestamp = if type(interactedAt) == "number" then interactedAt else 0
				if type(repoPath) == "string" and type(name) == "string" and name ~= "" and timestamp >= selectedAt then
					selectedDirectory = repoPath
					selectedBranch = name
					selectedAt = timestamp
				end
			end
		end
	end
	return selectedDirectory or workspaceDirectory, selectedBranch
end

function Cursor.new(options: Options?): types.Provider
	local resolved: Options = options or {}
	local home = resolved.homeDirectory or process.homedir()
	local databasePath = resolved.databasePath
		or path.join(home, "Library", "Application Support", "Cursor", "User", "globalStorage", "state.vscdb")
	local workspaceStorage = resolved.workspaceStoragePath
		or path.join(home, "Library", "Application Support", "Cursor", "User", "workspaceStorage")
	local runner = resolved.runner or defaultRun

	return {
		name = "cursor",
		sessions = function()
			if not fs.exists(databasePath) then
				return {}
			end
			local result = runner({
				"sqlite3",
				"-json",
				`file:{databasePath}?mode=ro`,
				"SELECT composerId, workspaceId, lastUpdatedAt, value FROM composerHeaders WHERE isArchived=0 AND isSubagent=0 ORDER BY lastUpdatedAt DESC;",
			})
			if not result.ok then
				return {}
			end
			local decodeOk, decoded = pcall(json.deserialize, result.stdout)
			local rows = if decodeOk then json.asArray(decoded) else nil
			if not rows then
				return {}
			end

			local sessions: { types.Session } = {}
			for _, rowValue in rows do
				local row = json.asObject(rowValue)
				local id = if row then row.composerId else nil
				local workspaceId = if row then row.workspaceId else nil
				local value = if row then row.value else nil
				if type(id) ~= "string" or type(value) ~= "string" then
					continue
				end
				local headerOk, headerValue = pcall(json.deserialize, value)
				local header = if headerOk then json.asObject(headerValue) else nil
				if not header then
					continue
				end
				local directory = if type(workspaceId) == "string"
					then workspaceDirectory(workspaceStorage, workspaceId)
					else nil
				local trackedDirectory, branch = trackedContext(header, directory)
				local rawUpdatedAt = header.lastUpdatedAt or (row :: json.Object).lastUpdatedAt
				local updatedAt = if type(rawUpdatedAt) == "number" then rawUpdatedAt else 0
				if updatedAt > 10_000_000_000 then
					updatedAt = math.floor(updatedAt / 1_000)
				end
				local name = header.name
				local filesChanged = header.filesChangedCount
				table.insert(sessions, {
					agent = "cursor" :: "cursor",
					id = id,
					title = if type(name) == "string" and name ~= "" then name else nil,
					directory = trackedDirectory,
					branchAtSessionTime = branch,
					updatedAt = updatedAt,
					needsAttention = header.hasUnreadMessages == true or header.hasBlockingPendingActions == true,
					filesChanged = if type(filesChanged) == "number" then filesChanged else nil,
					messages = providers.emptyMessages,
				})
			end
			return sessions
		end,
	}
end

return table.freeze(Cursor)
