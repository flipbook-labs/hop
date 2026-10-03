local json = require("@std/json")
local path = require("@std/path")
local test = require("@std/test")

local cache = require("@root/cache")
local cli = require("@root/cli")
local others = require("@root/others")
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
			if argv[1] == "gh" and argv[3] == "graphql" then
				return {
					ok = true,
					exitCode = 0,
					stdout = '{"data":{"branch1":{"pullRequests":{"nodes":[{"number":42,"headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42"}]}}}}',
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

-- One response serves both the branch lookup and the viewer's open PRs.
local pullRequestList = '{"data":{"branch2":{"defaultBranchRef":{"name":"main"},"openPullRequests":{"nodes":[]},"pullRequests":{"nodes":['
	.. '{"number":42,"title":"Add the hop command","headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42","state":"OPEN","isDraft":false}]}},'
	.. '"viewer":{"pullRequests":{"pageInfo":{"hasNextPage":false},"nodes":['
	.. '{"number":43,"title":"Orphaned idea","headRefName":"elsewhere","url":"https://github.com/example/widgets/pull/43","state":"OPEN","isDraft":true,"repository":{"nameWithOwner":"example/widgets"}}]}}}}'

local function pullRequestView(number: number, branch: string, crossRepository: boolean): string
	return json.serialize({
		number = number,
		title = `Change {number}`,
		url = `https://github.com/example/widgets/pull/{number}`,
		headRefName = branch,
		state = "OPEN",
		isDraft = false,
		isCrossRepository = crossRepository,
	})
end

-- `gh pr view` responses by PR number.
local pullRequestViews: { [string]: string } = {
	["5"] = pullRequestView(5, "thing/fix", false),
	["7"] = pullRequestView(7, "fix/thing", false),
	["8"] = pullRequestView(8, "main", true),
	["9"] = pullRequestView(9, "feature/hop", false),
	["10"] = pullRequestView(10, "existing", false),
	["43"] = pullRequestView(43, "elsewhere", false),
}

local SILO = "/home/me/.hop/cache"

local function memoryOthers(initial: { snapshot.Entry }?): (others.Store, { snapshot.Entry })
	local stored: { snapshot.Entry } = initial or {}
	return {
		read = function()
			return table.clone(stored)
		end,
		write = function(entries)
			table.clear(stored)
			table.move(entries, 1, #entries, 1, stored)
		end,
	},
		stored
end

local function toDependencies(
	commands: { { string } },
	output: { string },
	initial: snapshot.Snapshot?,
	otherStore: others.Store?
): (cli.Dependencies, { snapshot.Snapshot })
	local memory, writes = memoryCache(initial)
	return {
		others = otherStore or (memoryOthers()),
		write = function(value)
			table.insert(output, value)
		end,
		input = function()
			return "2"
		end,
		runner = function(argv)
			table.insert(commands, argv)
			if argv[1] == "gh" and argv[2] == "pr" then
				return { ok = true, exitCode = 0, stdout = pullRequestViews[argv[4]] or "", stderr = "" }
			elseif argv[1] == "gh" then
				return { ok = true, exitCode = 0, stdout = pullRequestList, stderr = "" }
			elseif argv[1] == "git" and argv[4] == "show-ref" then
				local exists = argv[#argv] == "refs/heads/pr-10"
				return { ok = exists, exitCode = if exists then 0 else 1, stdout = "", stderr = "" }
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

test.case("to opens a repository's default-branch checkout by keyword", function(assert)
	local commands: { { string } } = {}
	cli.execute({ "widgets", "default" }, (toDependencies(commands, {})))
	assert.eq(lastCommand(commands)[2], "/src/widgets")
end)

test.case("to lists the most recently used matches first", function(assert)
	for _, recent in { "/src/widgets", "/src/widgets-feature" } do
		local commands: { { string } } = {}
		local output: { string } = {}
		local dependencies = toDependencies(commands, output)
		dependencies.activity = function(worktree)
			return if tostring(worktree.path) == recent then 20 else 10
		end
		cli.execute({ "example" }, dependencies)
		assert.strContains(output[1], `1. widgets · {if recent == "/src/widgets" then "main" else "feature/hop"}`)
		assert.eq(lastCommand(commands)[2], if recent == "/src/widgets" then "/src/widgets-feature" else "/src/widgets")
	end
end)

test.case("to refreshes a stale cache once before giving up", function(assert)
	local commands: { { string } } = {}
	local stale = snapshot.build({ worktrees[1] }, {}, 0)
	local dependencies, writes = toDependencies(commands, {}, stale)
	cli.execute({ "feature/hop" }, dependencies)
	assert.eq(#writes, 1)
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
end)

test.case("to refreshes a cache whose matching worktree was removed", function(assert)
	local removed: types.Worktree = {
		path = path.parse("/nonexistent/hop-removed-worktree"),
		branch = "gone",
		repository = "example/widgets",
		primary = false,
	}
	local stale = snapshot.build({ worktrees[1], removed }, {}, 0)
	local dependencies, writes = toDependencies({}, {}, stale)
	local ok, message = pcall(cli.execute, { "gone" }, dependencies)
	assert.eq(ok, false)
	assert.strContains(tostring(message), 'nothing matches "gone"')
	assert.eq(#writes, 1)
end)

test.case("to still opens a worktree when the cache cannot be written", function(assert)
	local commands: { { string } } = {}
	local dependencies = toDependencies(commands, {})
	dependencies.cache = {
		read = function()
			return nil
		end,
		write = function(_value: snapshot.Snapshot): ()
			error("read-only file system")
		end,
	}
	cli.execute({ "feature/hop" }, dependencies)
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
end)

test.case("a failed GitHub lookup does not replace the cache", function(assert)
	local dependencies, writes = toDependencies({}, {})
	dependencies.runner = function()
		return { ok = false, exitCode = 1, stdout = "", stderr = "not authenticated" }
	end
	cli.execute({ "list", "--refresh" }, dependencies)
	assert.eq(#writes, 0)
end)

test.case("list only abbreviates paths inside the home directory", function(assert)
	local output: { string } = {}
	local dependencies = toDependencies({}, output)
	dependencies.homeDirectory = "/src/widgets"
	cli.execute({ "list" }, dependencies)
	assert.strContains(output[1], "\n    ~\n")
	assert.strContains(output[1], "\n    /src/widgets-feature")
end)

local function commandsFrom(commands: { { string } }, program: string): { string }
	local result: { string } = {}
	for _, argv in commands do
		if argv[1] == program then
			table.insert(result, table.concat(argv, " "))
		end
	end
	return result
end

test.case("to checks out someone else's PR URL under the cache, linked to your clone", function(assert)
	local commands: { { string } } = {}
	local output: { string } = {}
	local store, stored = memoryOthers()
	local dependencies, writes = toDependencies(commands, output, nil, store)
	cli.execute({ "https://github.com/Example/Widgets/pull/7" }, dependencies)

	local destination = `{SILO}/worktrees/example/widgets-pr-7`
	local gitCommands = commandsFrom(commands, "git")
	assert.eq(gitCommands[1], "git -C /src/widgets worktree list --porcelain")
	assert.eq(gitCommands[2], "git -C /src/widgets fetch origin refs/pull/7/head")
	assert.eq(gitCommands[3], "git -C /src/widgets show-ref --verify --quiet refs/heads/pr-7")
	assert.eq(gitCommands[4], `git -C /src/widgets worktree add -b pr-7 {destination} FETCH_HEAD`)
	assert.eq(table.concat(lastCommand(commands), " "), `code {destination}`)
	assert.strContains(output[1], `Checked out Example/Widgets#7 in {destination}`)

	assert.eq(#stored, 1)
	assert.eq(tostring(stored[1].worktree.path), destination)
	assert.eq(stored[1].worktree.repository, "example/widgets")
	local pullRequest = stored[1].pullRequest
	assert.eq(pullRequest and pullRequest.number, 7)
	for _, cached in writes do
		for _, entry in cached.entries do
			assert.neq(tostring(entry.worktree.path), destination)
		end
	end
end)

test.case("to reopens others' work by reference without asking GitHub", function(assert)
	local commands: { { string } } = {}
	local destination = `{SILO}/worktrees/example/widgets-pr-7`
	local store = memoryOthers({
		{
			worktree = {
				path = path.parse(destination),
				branch = "fix/thing",
				repository = "example/widgets",
				primary = false,
			},
			pullRequest = {
				number = 7,
				url = "https://github.com/example/widgets/pull/7",
				branch = "fix/thing",
				repository = "example/widgets",
			},
		},
	})
	for _, expression in { "#7", "widgets#7", "https://github.com/example/widgets/pull/7" } do
		cli.execute({ expression }, (toDependencies(commands, {}, snapshot.build(worktrees, {}, 0), store)))
		assert.eq(lastCommand(commands)[2], destination)
	end
	assert.eq(#commandsFrom(commands, "gh"), 0)
	assert.eq(#commandsFrom(commands, "git"), 0)
end)

test.case("others' work never matches search words", function(assert)
	local store = memoryOthers({
		{
			worktree = {
				path = path.parse(`{SILO}/worktrees/example/widgets-pr-7`),
				branch = "fix/thing",
				repository = "example/widgets",
				primary = false,
			},
			pullRequest = nil,
		},
	})
	local ok, message = pcall(cli.execute, { "fix/thing" }, (toDependencies({}, {}, nil, store)))
	assert.eq(ok, false)
	assert.strContains(tostring(message), 'nothing matches "fix/thing"')
end)

test.case("to checks out fork PRs from refs/pull into a PR-named branch", function(assert)
	local commands: { { string } } = {}
	cli.execute({ "example/widgets#8" }, (toDependencies(commands, {})))
	local gitCommands = commandsFrom(commands, "git")
	assert.eq(gitCommands[2], "git -C /src/widgets fetch origin refs/pull/8/head")
	assert.eq(
		gitCommands[4],
		`git -C /src/widgets worktree add -b pr-8 {SILO}/worktrees/example/widgets-pr-8 FETCH_HEAD`
	)
end)

test.case("to fast-forwards and reuses an existing local branch for a PR checkout", function(assert)
	local commands: { { string } } = {}
	cli.execute({ "widgets#10" }, (toDependencies(commands, {})))
	local gitCommands = commandsFrom(commands, "git")
	assert.eq(gitCommands[4], "git -C /src/widgets fetch origin refs/pull/10/head:refs/heads/pr-10")
	assert.eq(gitCommands[5], `git -C /src/widgets worktree add {SILO}/worktrees/example/widgets-pr-10 pr-10`)
end)

test.case(
	"to treats a worktree of yours on the PR's branch as your own, even when the cache missed it",
	function(assert)
		local commands: { { string } } = {}
		local store, stored = memoryOthers()
		local dependencies, writes = toDependencies(commands, {}, snapshot.build(worktrees, {}, 0), store)
		local runner = dependencies.runner or error("expected a runner")
		dependencies.runner = function(argv)
			if argv[1] == "git" and argv[4] == "worktree" and argv[5] == "list" then
				table.insert(commands, argv)
				return {
					ok = true,
					exitCode = 0,
					stdout = "worktree /src/widgets\nbranch refs/heads/main\n\nworktree /src/widgets-fix\nbranch refs/heads/fix/thing\n",
					stderr = "",
				}
			end
			return runner(argv)
		end
		cli.execute({ "example/widgets#7" }, dependencies)
		assert.eq(lastCommand(commands)[2], "/src/widgets-fix")
		assert.eq(#stored, 0)
		local cached = writes[#writes]
		local entry = cached.entries[#cached.entries]
		assert.eq(tostring(entry.worktree.path), "/src/widgets-fix")
		assert.eq(entry.pullRequest and entry.pullRequest.number, 7)
	end
)

test.case("bare numbers are search words that match repo#123", function(assert)
	local commands: { { string } } = {}
	cli.execute({ "42" }, (toDependencies(commands, {})))
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
	assert.eq(#commandsFrom(commands, "git"), 0)
end)

test.case("to opens a worktree already on a PR's branch instead of adding one", function(assert)
	local commands: { { string } } = {}
	local output: { string } = {}
	cli.execute({ "example/widgets#9" }, (toDependencies(commands, output)))
	assert.eq(#commandsFrom(commands, "git"), 0)
	assert.eq(#output, 0)
	assert.eq(lastCommand(commands)[2], "/src/widgets-feature")
end)

test.case("to checks out the viewer's PR that has no worktree and drops it from the orphan list", function(assert)
	local commands: { { string } } = {}
	local dependencies, writes = toDependencies(commands, {})
	cli.execute({ "#43" }, dependencies)
	assert.eq(lastCommand(commands)[2], "/src/widgets-pr-43")
	assert.eq(#writes[#writes].pullRequests, 0)
end)

test.case("to refreshes the cache before filing your new PR as someone else's", function(assert)
	local commands: { { string } } = {}
	local store, stored = memoryOthers()
	cli.execute({ "example/widgets#43" }, (toDependencies(commands, {}, snapshot.build(worktrees, {}, 0), store)))
	assert.eq(lastCommand(commands)[2], "/src/widgets-pr-43")
	assert.eq(#stored, 0)
end)

test.case("to refreshes a cached PR that has since gained a worktree instead of adding another", function(assert)
	local commands: { { string } } = {}
	local orphan: types.PullRequest = {
		number = 43,
		url = "https://github.com/example/widgets/pull/43",
		branch = "elsewhere",
		repository = "example/widgets",
		state = "OPEN",
	}
	local dependencies = toDependencies(commands, {}, snapshot.build(worktrees, { orphan }, 0))
	dependencies.loadWorktrees = function()
		local all = table.clone(worktrees)
		table.insert(all, {
			path = path.parse("/src/widgets-elsewhere"),
			branch = "elsewhere",
			repository = "example/widgets",
			primary = false,
		})
		return all
	end
	cli.execute({ "#43" }, dependencies)
	assert.eq(lastCommand(commands)[2], "/src/widgets-elsewhere")
	assert.eq(#commandsFrom(commands, "git"), 0)
end)

test.case("to keeps records another Hop process wrote during a checkout", function(assert)
	local commands: { { string } } = {}
	local store, stored = memoryOthers()
	local read = store.read
	local reads = 0
	store.read = function()
		reads += 1
		if reads == 2 then
			table.insert(stored, {
				worktree = {
					path = path.parse(`{SILO}/worktrees/example/widgets-pr-9`),
					branch = "pr-9",
					repository = "example/widgets",
					primary = false,
				},
				pullRequest = nil,
			})
		end
		return read()
	end
	cli.execute({ "example/widgets#7" }, (toDependencies(commands, {}, nil, store)))
	assert.eq(#stored, 2)
	assert.eq(tostring(stored[1].worktree.path), `{SILO}/worktrees/example/widgets-pr-9`)
	assert.eq(tostring(stored[2].worktree.path), `{SILO}/worktrees/example/widgets-pr-7`)
end)

test.case("to clones a repository you do not have into the cache", function(assert)
	local commands: { { string } } = {}
	local store, stored = memoryOthers()
	cli.execute({ "other/thing#5" }, (toDependencies(commands, {}, nil, store)))
	local clone = `{SILO}/repos/other/thing`
	local ghCommands = commandsFrom(commands, "gh")
	assert.eq(ghCommands[#ghCommands], `gh repo clone other/thing {clone} -- --filter=blob:none`)
	local gitCommands = commandsFrom(commands, "git")
	assert.eq(gitCommands[1], `git -C {clone} fetch origin refs/pull/5/head`)
	assert.eq(lastCommand(commands)[2], `{SILO}/worktrees/other/thing-pr-5`)
	assert.eq(stored[1].worktree.root, clone)
end)

test.case("list --refresh leaves others' work out of your worktrees and reports it separately", function(assert)
	local output: { string } = {}
	local destination = `{SILO}/worktrees/example/widgets-pr-7`
	local store = memoryOthers({
		{
			worktree = {
				path = path.parse(destination),
				branch = "fix/thing",
				repository = "example/widgets",
				primary = false,
			},
			pullRequest = nil,
		},
	})
	local dependencies = toDependencies({}, output, nil, store)
	dependencies.loadWorktrees = function()
		local all = table.clone(worktrees)
		table.insert(
			all,
			{ path = path.parse(destination), branch = "fix/thing", repository = "example/widgets", primary = false }
		)
		return all
	end
	cli.execute({ "list", "--refresh", "--json" }, dependencies)
	local value = json.asObject(json.deserialize(output[1])) or error("expected JSON object")
	assert.eq(#(json.asArray(value.worktrees) or {}), 2)
	local otherItems = json.asArray(value.others) or error("expected others")
	local other = json.asObject(otherItems[1]) or error("expected an entry")
	assert.eq(other.path, destination)

	cli.execute({ "list" }, dependencies)
	assert.strContains(output[2], "Others' pull requests")
	assert.strContains(output[2], "~/.hop/cache/worktrees/example/widgets-pr-7")
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

test.case("list --json reports the default branch and live activity", function(assert)
	local output: { string } = {}
	local dependencies = toDependencies({}, output)
	dependencies.activity = function(worktree)
		return if tostring(worktree.path) == "/src/widgets" then 50 else 10
	end
	cli.execute({ "list", "--json" }, dependencies)
	local value = json.asObject(json.deserialize(output[1])) or error("expected JSON object")
	local items = json.asArray(value.worktrees) or error("expected worktrees")
	local primary = json.asObject(items[1]) or error("expected worktree")
	local feature = json.asObject(items[2]) or error("expected worktree")
	assert.eq(primary.onDefaultBranch, true)
	assert.eq(primary.lastActivity, 50)
	assert.eq(feature.onDefaultBranch, false)
	assert.eq(feature.lastActivity, 10)
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
