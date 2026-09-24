local json = require("@std/json")
local path = require("@std/path")
local test = require("@std/test")

local cache = require("@root/cache")
local cli = require("@root/cli")
local providers = require("@root/providers")
local snapshot = require("@root/core/snapshot")
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

local function memoryCache(initial: snapshot.Snapshot?): (cache.Cache, { snapshot.Snapshot })
	local writes: { snapshot.Snapshot } = {}
	local current = initial
	return {
		read = function()
			return current
		end,
		write = function(value)
			current = value
			table.insert(writes, value)
		end,
	},
		writes
end

local pullRequestList = '[{"number":42,"title":"Add the hop command","headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42","state":"OPEN","isDraft":false},'
	.. '{"number":43,"title":"Orphaned idea","headRefName":"elsewhere","url":"https://github.com/example/widgets/pull/43","state":"OPEN","isDraft":true}]'

local function toDependencies(
	commands: { { string } },
	output: { string },
	initial: snapshot.Snapshot?
): (cli.Dependencies, { snapshot.Snapshot })
	local memory, writes = memoryCache(initial)
	return {
		write = function(value)
			table.insert(output, value)
		end,
		input = function()
			return "2"
		end,
		runner = function(argv)
			table.insert(commands, argv)
			if argv[1] == "gh" then
				return { ok = true, exitCode = 0, stdout = pullRequestList, stderr = "" }
			end
			return { ok = true, exitCode = 0, stdout = "", stderr = "" }
		end,
		homeDirectory = "/home/me",
		loadWorktrees = function()
			return worktrees
		end,
		cache = memory,
		now = function()
			return 1000
		end,
	},
		writes
end

local function lastCommand(commands: { { string } }): { string }
	return commands[#commands]
end

local function helpOutput(args: { string }): string
	local output = ""
	cli.execute(args, {
		write = function(value)
			output = value
		end,
	})
	return output
end

test.case("no arguments, --help, -h, and help all print the root help", function(assert)
	local expected = helpOutput({})
	assert.strContains(expected, "Usage: hop <command>")
	for _, args in { { "--help" }, { "-h" }, { "help" } } do
		assert.eq(helpOutput(args), expected)
	end
end)

test.case("command help comes from --help or help <command>", function(assert)
	local output = helpOutput({ "list", "--help" })
	assert.strContains(output, "Usage: hop list [options]")
	assert.strContains(output, "--no-pr")
	assert.eq(helpOutput({ "help", "list" }), output)
end)

test.case("help rejects unknown commands", function(assert)
	local dependencies: cli.Dependencies = { write = function() end }
	local ok, message = pcall(cli.execute, { "help", "nope" }, dependencies)
	assert.eq(ok, false)
	assert.strContains(tostring(message), "unknown command: nope")
end)

test.case("unknown options are rejected", function(assert)
	local ok, message = pcall(cli.execute, { "list", "--bogus" }, (toDependencies({}, {})))
	assert.eq(ok, false)
	assert.strContains(tostring(message), "Unknown argument: bogus")
end)

test.case("expressions may contain command names after the first word", function(assert)
	local ok, message = pcall(cli.execute, { "widgets", "list" }, (toDependencies({}, {})))
	assert.eq(ok, false)
	assert.strContains(tostring(message), 'nothing matches "widgets list"')
end)

test.case("bare expressions open the matching PR worktree", function(assert)
	for _, expression in { "example/widgets#42", "widgets#42", "#42", "https://github.com/example/widgets/pull/42" } do
		local commands: { { string } } = {}
		cli.execute({ expression }, (toDependencies(commands, {})))
		assert.eq(lastCommand(commands)[1], "code")
		assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
	end
end)

test.case("to matches PR titles and multi-word queries", function(assert)
	local commands: { { string } } = {}
	cli.execute({ "to", "hop", "command" }, (toDependencies(commands, {})))
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
end)

test.case("to picks from ambiguous matches with the numbered picker", function(assert)
	local commands: { { string } } = {}
	local output: { string } = {}
	cli.execute({ "widgets" }, (toDependencies(commands, output)))
	assert.strContains(output[1], "1. widgets · main · no PR")
	assert.strContains(output[1], "2. widgets · feature/hop · #42 Add the hop command (open)")
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
end)

test.case("to refreshes a stale cache once before giving up", function(assert)
	local commands: { { string } } = {}
	local stale = snapshot.build({ worktrees[1] }, {}, 0)
	local dependencies, writes = toDependencies(commands, {}, stale)
	cli.execute({ "feature/hop" }, dependencies)
	assert.eq(#writes, 1)
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
end)

test.case("to reports PRs that have no local worktree", function(assert)
	local ok, message = pcall(cli.execute, { "#43" }, (toDependencies({}, {})))
	assert.eq(ok, false)
	assert.strContains(tostring(message), "no local worktree")
	assert.strContains(tostring(message), "https://github.com/example/widgets/pull/43")
end)

test.case("list prints worktrees, PRs, and orphaned PRs for humans", function(assert)
	local output: { string } = {}
	cli.execute({ "list" }, (toDependencies({}, output)))
	assert.strContains(output[1], "widgets · feature/hop · #42 Add the hop command (open)")
	assert.strContains(output[1], "Open pull requests without a local worktree")
	assert.strContains(output[1], "#43 Orphaned idea (draft)")
end)

test.case("list --json serves the cache and --refresh rebuilds it", function(assert)
	local commands: { { string } } = {}
	local output: { string } = {}
	local cached = snapshot.build(worktrees, {}, 900)
	local dependencies, writes = toDependencies(commands, output, cached)
	cli.execute({ "list", "--json" }, dependencies)
	assert.eq(#commands, 0)
	local value = json.asObject(json.deserialize(output[1])) or error("expected JSON object")
	assert.eq(value.generatedAt, 900)

	cli.execute({ "list", "--json", "--refresh" }, dependencies)
	assert.eq(#writes, 1)
	local refreshed = json.asObject(json.deserialize(output[2])) or error("expected JSON object")
	local items = json.asArray(refreshed.worktrees) or error("expected worktrees")
	local feature = json.asObject(items[2]) or error("expected worktree")
	local pr = json.asObject(feature.pr) or error("expected PR")
	local repository = json.asObject(feature.repository) or error("expected repository")
	assert.eq(pr.number, 42)
	assert.eq(pr.title, "Add the hop command")
	assert.eq(repository.name, "widgets")
	assert.eq(repository.remote, "example/widgets")
end)

test.case("list --no-pr skips gh and leaves the cache alone", function(assert)
	local commands: { { string } } = {}
	local dependencies, writes = toDependencies(commands, {})
	cli.execute({ "list", "--refresh", "--no-pr" }, dependencies)
	assert.eq(#commands, 0)
	assert.eq(#writes, 0)
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
	for _, command in { "hop <expr>", "to", "list", "recent", "cursor", "help" } do
		assert.strContains(output, command)
	end
end)
