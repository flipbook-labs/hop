local json = require("@std/json")
local path = require("@std/path")
local test = require("@std/test")

local cli = require("@root/cli")
local providers = require("@root/providers")
local types = require("@root/types")

local worktrees: { types.Worktree } = {
	{
		path = path.parse("/src/widgets"),
		branch = "main",
		repository = "example/widgets",
		primary = true,
	},
	{
		path = path.parse("/src/widgets-feature"),
		branch = "feature/hop",
		repository = "example/widgets",
		primary = false,
	},
}

local sessions: { types.Session } = {
	{
		agent = "cursor",
		id = "cursor-1",
		title = "Implement Hop",
		directory = "/src/widgets-feature",
		branchAtSessionTime = "feature/hop",
		updatedAt = 200,
		needsAttention = true,
		filesChanged = 3,
		messages = providers.emptyMessages,
	},
	{
		agent = "claude",
		id = "claude-1",
		title = "Review widgets",
		directory = "/src/widgets",
		branchAtSessionTime = "main",
		updatedAt = 100,
		needsAttention = false,
		filesChanged = nil,
		messages = providers.emptyMessages,
	},
}

local function baseDependencies(write: (string) -> ()): cli.Dependencies
	return {
		write = write,
		runner = function(argv)
			if argv[1] == "gh" and argv[3] == "list" then
				return {
					ok = true,
					exitCode = 0,
					stdout = '[{"number":42,"headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42"}]',
					stderr = "",
				}
			end
			return { ok = true, exitCode = 0, stdout = "", stderr = "" }
		end,
		loadSessions = function()
			return sessions
		end,
		loadWorktrees = function()
			return worktrees
		end,
	}
end

test.case("recent filters providers and emits normalized JSON", function(assert)
	local output = ""
	cli.execute(
		{ "recent", "--agent", "cursor", "--limit", "1", "--json" },
		baseDependencies(function(value)
			output = value
		end)
	)
	local values = json.asArray(json.deserialize(output)) or error("expected JSON array")
	local item = json.asObject(values[1]) or error("expected JSON object")
	assert.eq(#values, 1)
	assert.eq(item.agent, "cursor")
	assert.eq(item.repository, "example/widgets")
	assert.eq(item.branch, "feature/hop")
	assert.eq(item.pullRequest, 42)
end)

test.case("recent renders attention, repository, branch, PR, and worktree", function(assert)
	local output = ""
	cli.execute(
		{ "recent", "--limit", "1" },
		baseDependencies(function(value)
			output = value
		end)
	)
	assert.strContains(output, "[cursor] !")
	assert.strContains(output, "example/widgets")
	assert.strContains(output, "feature/hop")
	assert.strContains(output, "PR #42")
	assert.strContains(output, "/src/widgets-feature")
end)

test.case("go uses a numbered picker and opens with plain code folder", function(assert)
	local commands: { { string } } = {}
	local output: { string } = {}
	local dependencies = baseDependencies(function(value)
		table.insert(output, value)
	end)
	dependencies.input = function()
		return "2"
	end
	dependencies.runner = function(argv)
		table.insert(commands, argv)
		return { ok = true, exitCode = 0, stdout = "", stderr = "" }
	end
	cli.execute({ "go" }, dependencies)
	assert.strContains(output[1], "1.")
	assert.eq(commands[1][1], "code")
	assert.eq(commands[1][2], "/src/widgets")
	assert.eq(#commands[1], 2)
end)

test.case("pr resolves with gh and opens the existing head worktree", function(assert)
	local commands: { { string } } = {}
	local dependencies = baseDependencies(function() end)
	dependencies.runner = function(argv)
		table.insert(commands, argv)
		if argv[1] == "gh" and argv[2] == "search" then
			return {
				ok = true,
				exitCode = 0,
				stdout = '[{"number":42,"url":"https://github.com/example/widgets/pull/42","repository":{"nameWithOwner":"example/widgets"}}]',
				stderr = "",
			}
		elseif argv[1] == "gh" then
			return {
				ok = true,
				exitCode = 0,
				stdout = '{"number":42,"url":"https://github.com/example/widgets/pull/42","headRefName":"feature/hop","headRepository":{"nameWithOwner":"example/widgets"}}',
				stderr = "",
			}
		end
		return { ok = true, exitCode = 0, stdout = "", stderr = "" }
	end
	cli.execute({ "pr", "42" }, dependencies)
	assert.eq(commands[1][1], "gh")
	assert.eq(commands[2][1], "gh")
	assert.eq(commands[3][1], "code")
	assert.eq(commands[3][2], "/src/widgets-feature")
end)

test.case("cursor resumes the selected session in its workspace", function(assert)
	local command: { string } = {}
	local dependencies = baseDependencies(function() end)
	dependencies.runner = function(argv)
		command = argv
		return { ok = true, exitCode = 0, stdout = "", stderr = "" }
	end
	cli.execute({ "cursor", "Implement" }, dependencies)
	assert.eq(command[1], "agent")
	assert.eq(command[2], "--workspace")
	assert.eq(command[3], "/src/widgets-feature")
	assert.eq(command[4], "--resume")
	assert.eq(command[5], "cursor-1")
end)

test.case("help describes every public command", function(assert)
	local output = ""
	cli.execute({ "help" }, {
		write = function(value)
			output = value
		end,
	})
	for _, command in { "recent", "go", "pr", "cursor", "help" } do
		assert.strContains(output, command)
	end
end)
