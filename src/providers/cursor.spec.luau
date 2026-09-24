local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local test = require("@std/test")

local Cursor = require("@root/providers/cursor")
local types = require("@root/types")

local function fixture(): (path.Path, path.Path, path.Path)
	local root = path.join(system.tmpdir(), `hop-cursor-{process.pid()}`)
	if fs.exists(root) then
		fs.removeDirectory(root, { recursive = true })
	end
	local database = path.join(root, "state.vscdb")
	local storage = path.join(root, "workspaceStorage")
	fs.createDirectory(path.join(storage, "workspace-1"), { makeParents = true })
	fs.writeStringToFile(database, "")
	fs.writeStringToFile(path.join(storage, "workspace-1", "workspace.json"), '{"folder":"file:///src/workspace"}')
	return root, database, storage
end

test.case("Cursor reads active top-level sessions through sqlite read-only mode", function(assert)
	local _, database, storage = fixture()
	local command: { string } = {}
	local header = json.serialize({
		name = "Implement provider",
		lastUpdatedAt = 1_700_000_123_000,
		hasUnreadMessages = true,
		hasBlockingPendingActions = false,
		filesChangedCount = 4,
		trackedGitRepos = {
			{
				repoPath = "/src/example repo",
				branches = { { branchName = "feature/provider" } },
			},
		},
	})
	local provider = Cursor.new({
		databasePath = database,
		workspaceStoragePath = storage,
		runner = function(argv)
			command = argv
			local rows: json.Array = {
				{
					composerId = "composer-1",
					workspaceId = "workspace-1",
					lastUpdatedAt = 1_700_000_123_000,
					value = header,
				},
				{
					composerId = "composer-2",
					workspaceId = "workspace-1",
					lastUpdatedAt = 1_700_000_000_000,
					value = json.serialize({ name = "Workspace session", lastUpdatedAt = 1_700_000_000_000 }),
				},
			}
			return {
				ok = true,
				exitCode = 0,
				stdout = json.serialize(rows),
				stderr = "",
			} :: types.CommandResult
		end,
	})
	local sessions = provider:sessions()
	assert.eq(command[1], "sqlite3")
	assert.strContains(command[3], "mode=ro")
	assert.strContains(command[4], "isArchived=0 AND isSubagent=0")
	assert.eq(#sessions, 2)
	assert.eq(sessions[1].directory, "/src/example repo")
	assert.eq(sessions[1].branchAtSessionTime, "feature/provider")
	assert.eq(sessions[1].updatedAt, 1_700_000_123)
	assert.eq(sessions[1].needsAttention, true)
	assert.eq(sessions[1].filesChanged, 4)
	assert.eq(sessions[2].directory, "/src/workspace")
end)

test.case("Cursor degrades to no sessions when sqlite is unavailable", function(assert)
	local _, database, storage = fixture()
	local provider = Cursor.new({
		databasePath = database,
		workspaceStoragePath = storage,
		runner = function()
			return { ok = false, exitCode = 127, stdout = "", stderr = "missing" }
		end,
	})
	assert.eq(#provider:sessions(), 0)
end)
