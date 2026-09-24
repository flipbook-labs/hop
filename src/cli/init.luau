local batteriesCli = require("@batteries/cli")
local io = require("@std/io")
local json = require("@std/json")
local path = require("@std/path")
local process = require("@std/process")

local Claude = require("@root/providers/claude")
local Cursor = require("@root/providers/cursor")
local cache = require("@root/cache")
local defaultRun = require("@root/command")
local editor = require("@root/editor")
local git = require("@root/git")
local github = require("@root/github")
local loadConfig = require("@root/config/load")
local matchWorktrees = require("@root/core/matchWorktrees")
local providers = require("@root/providers")
local render = require("@root/render")
local resolve = require("@root/core/resolve")
local snapshot = require("@root/core/snapshot")
local types = require("@root/types")

type RecentItem = render.RecentItem

export type Dependencies = {
	runner: types.CommandRunner?,
	input: (() -> string?)?,
	write: ((string) -> ())?,
	homeDirectory: path.Pathlike?,
	loadSessions: (() -> { types.Session })?,
	loadWorktrees: (() -> { types.Worktree })?,
	cache: cache.Cache?,
	now: (() -> number)?,
}

type Resolved = {
	runner: types.CommandRunner,
	input: () -> string?,
	write: (string) -> (),
	homeDirectory: string,
	loadWorktrees: () -> { types.Worktree },
	loadSessions: () -> { types.Session },
	cache: cache.Cache,
	now: () -> number,
}

type RecentOptions = {
	limit: number,
	repository: string?,
	agent: string?,
	json: boolean,
}

type ListOptions = {
	refresh: boolean,
	pullRequests: boolean,
	json: boolean,
}

local COMMANDS: { [string]: boolean } = {
	to = true,
	list = true,
	recent = true,
	cursor = true,
	help = true,
}

local HELP = [[
hop — jump from agent sessions and pull requests to local worktrees

USAGE:
  hop <expr>                  Same as `hop to <expr>`
  hop to <expr>               Open the worktree matching <expr> in VS Code
  hop list [--refresh] [--no-pr] [--json]
  hop recent [--limit N] [--repo OWNER/REPO] [--agent cursor|claude] [--json]
  hop cursor [NUMBER|QUERY]
  hop help

EXPRESSIONS:
  owner/repo#123, repo#123, #123, 123, or a PR URL
  otherwise a branch, repository, folder name, or PR title fragment
]]

local function route(args: { string }): (string, { string })
	local first = args[1]
	if first == nil or first == "help" or first == "--help" or first == "-h" then
		return "help", {}
	end
	if COMMANDS[first] then
		return first, { table.unpack(args, 2) }
	end
	return "to", args
end

local function recentOptions(args: { string }): RecentOptions
	local parser = batteriesCli.parser()
	parser:add("limit", "option", { default = "20" })
	parser:add("repo", "option", {})
	parser:add("agent", "option", {})
	parser:add("json", "flag", {})
	parser:parse(args)

	local limit = tonumber(parser:get("limit"))
	assert(limit and limit >= 0 and limit % 1 == 0, "--limit must be a non-negative integer")
	local agent = parser:get("agent")
	assert(agent == nil or agent == "cursor" or agent == "claude", "--agent must be cursor or claude")
	return {
		limit = limit,
		repository = parser:get("repo"),
		agent = agent,
		json = parser:has("json"),
	}
end

local function listOptions(args: { string }): ListOptions
	local parser = batteriesCli.parser()
	parser:add("refresh", "flag", {})
	parser:add("no-pr", "flag", {})
	parser:add("json", "flag", {})
	parser:parse(args)
	return {
		refresh = parser:has("refresh"),
		pullRequests = not parser:has("no-pr"),
		json = parser:has("json"),
	}
end

local function dependencies(options: Dependencies?): Resolved
	local resolved: Dependencies = options or {}
	local runner = resolved.runner or defaultRun
	local home = tostring(resolved.homeDirectory or process.homedir())
	return {
		runner = runner,
		input = resolved.input or function()
			return io.input()
		end,
		write = resolved.write or print,
		homeDirectory = home,
		loadWorktrees = resolved.loadWorktrees or function()
			local config = loadConfig({ homeDirectory = home })
			return git.discover(config.roots, { runner = runner })
		end,
		loadSessions = resolved.loadSessions or function()
			return providers.collect({
				Cursor.new({ homeDirectory = home, runner = runner }),
				Claude.new({ homeDirectory = home }),
			})
		end,
		cache = resolved.cache or cache.new(home),
		now = resolved.now or function()
			return os.time()
		end,
	}
end

-- Returns the cached snapshot when allowed, otherwise rebuilds it from Git and GitHub.
-- Local-only rebuilds are not cached so they never discard known PR associations.
local function loadSnapshot(
	deps: Resolved,
	refresh: boolean,
	includePullRequests: boolean
): (snapshot.Snapshot, boolean)
	if not refresh then
		local cached = deps.cache.read()
		if cached then
			return cached, true
		end
	end
	local worktrees = deps.loadWorktrees()
	local pullRequests = if includePullRequests then github.listPullRequests(worktrees, deps.runner) else {}
	local value = snapshot.build(worktrees, pullRequests, deps.now())
	if includePullRequests then
		deps.cache.write(value)
	end
	return value, false
end

local function worktreeForSession(session: types.Session, worktrees: { types.Worktree }): types.Worktree?
	if session.directory then
		for _, worktree in worktrees do
			if tostring(worktree.path) == session.directory then
				return worktree
			end
		end
	end
	if session.branchAtSessionTime then
		local matches = matchWorktrees(worktrees, session.branchAtSessionTime)
		if matches[1] then
			return matches[1]
		end
	end
	if session.directory then
		local matches = matchWorktrees(worktrees, session.directory)
		if matches[1] then
			return matches[1]
		end
	end
	return nil
end

local function recentItems(sessions: { types.Session }, worktrees: { types.Worktree }): { RecentItem }
	local items: { RecentItem } = {}
	for _, session in sessions do
		table.insert(items, {
			session = session,
			worktree = worktreeForSession(session, worktrees),
			pullRequest = nil,
		})
	end
	return items
end

local function filteredRecent(items: { RecentItem }, options: RecentOptions): { RecentItem }
	local result: { RecentItem } = {}
	if options.limit == 0 then
		return result
	end
	local repositoryFilter = if options.repository then options.repository:lower() else nil
	for _, item in items do
		if options.agent and item.session.agent ~= options.agent then
			continue
		end
		if repositoryFilter then
			local repository = if item.worktree and item.worktree.repository
				then item.worktree.repository:lower()
				else ""
			local directory = (if item.worktree then tostring(item.worktree.path) else item.session.directory or ""):lower()
			if not repository:find(repositoryFilter, 1, true) and not directory:find(repositoryFilter, 1, true) then
				continue
			end
		end
		table.insert(result, item)
		if #result >= options.limit then
			break
		end
	end
	return result
end

local function attachPullRequests(items: { RecentItem }, runner: types.CommandRunner)
	local worktrees: { types.Worktree } = {}
	for _, item in items do
		if item.worktree then
			table.insert(worktrees, item.worktree)
		end
	end
	local pullRequests = github.indexPullRequests(github.listPullRequests(worktrees, runner))
	for _, item in items do
		local worktree = item.worktree
		if worktree and worktree.repository and worktree.branch then
			item.pullRequest = pullRequests[github.pullRequestKey(worktree.repository, worktree.branch)]
		end
	end
end

local function itemJson(item: RecentItem): json.Object
	local session = item.session
	local worktree = item.worktree
	return {
		agent = session.agent,
		id = session.id,
		title = session.title,
		directory = if worktree then tostring(worktree.path) else session.directory,
		branch = if worktree then worktree.branch else session.branchAtSessionTime,
		repository = if worktree then worktree.repository else nil,
		pullRequest = if item.pullRequest then item.pullRequest.number else nil,
		pullRequestUrl = if item.pullRequest then item.pullRequest.url else nil,
		updatedAt = session.updatedAt,
		needsAttention = session.needsAttention,
		filesChanged = session.filesChanged,
	}
end

local function itemWorktree(item: RecentItem): types.Worktree?
	if item.worktree then
		return item.worktree
	end
	if item.session.directory then
		return {
			path = path.parse(item.session.directory),
			branch = item.session.branchAtSessionTime,
			repository = nil,
			primary = false,
		}
	end
	return nil
end

local function selectItem(
	items: { RecentItem },
	query: string?,
	input: () -> string?,
	write: (string) -> ()
): RecentItem?
	if query == nil then
		return render.choose(items, input, write)
	end
	local index = tonumber(query)
	if index and index % 1 == 0 then
		return items[index]
	end
	local normalized = query:lower()
	local matches: { RecentItem } = {}
	for _, item in items do
		local title = (item.session.title or ""):lower()
		local id = item.session.id:lower()
		local branch = (item.session.branchAtSessionTime or ""):lower()
		if title:find(normalized, 1, true) or id:find(normalized, 1, true) or branch:find(normalized, 1, true) then
			table.insert(matches, item)
		end
	end
	return render.choose(matches, input, write)
end

local function age(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{seconds // 60}m ago`
	elseif seconds < 86400 then
		return `{seconds // 3600}h ago`
	end
	return `{seconds // 86400}d ago`
end

local function list(deps: Resolved, options: ListOptions)
	local value, cached = loadSnapshot(deps, options.refresh, options.pullRequests)
	if options.json then
		deps.write(json.serialize(snapshot.toJson(value), true))
		return
	end
	local sections: { string } = {}
	if #value.entries > 0 then
		table.insert(
			sections,
			render.numberedWith(value.entries, function(entry)
				return render.entryLabel(entry, deps.homeDirectory)
			end)
		)
	else
		table.insert(sections, "No worktrees found.")
	end
	if #value.pullRequests > 0 then
		table.insert(
			sections,
			"Open pull requests without a local worktree:\n"
				.. render.numberedWith(value.pullRequests, render.pullRequestLabel)
		)
	end
	if cached then
		table.insert(sections, `Cached {age(deps.now() - value.generatedAt)}; run \`hop list --refresh\` to update.`)
	end
	deps.write(table.concat(sections, "\n\n"))
end

local function noWorktreeMessage(expression: string, pullRequests: { types.PullRequest }): string
	if #pullRequests == 0 then
		return `nothing matches "{expression}"`
	end
	local lines = { `no local worktree for "{expression}"; matching pull requests:` }
	for _, pullRequest in pullRequests do
		table.insert(lines, `  {pullRequest.repository}#{pullRequest.number} {pullRequest.url}`)
	end
	return table.concat(lines, "\n")
end

local function to(deps: Resolved, args: { string })
	local text = table.concat(args, " ")
	assert(text:match("%S"), "usage: hop to <expr>")
	local expression = resolve.parse(text)
	local value, cached = loadSnapshot(deps, false, true)
	local resolution = resolve.resolve(value, expression)
	if #resolution.entries == 0 and cached then
		-- The worktree may be newer than the cache, such as one an agent just created.
		value = loadSnapshot(deps, true, true)
		resolution = resolve.resolve(value, expression)
	end
	if #resolution.entries == 0 then
		error(noWorktreeMessage(text, resolution.pullRequests), 0)
	end
	local selected = render.chooseWith(resolution.entries, function(entry)
		return render.entryLabel(entry, deps.homeDirectory)
	end, deps.input, deps.write)
	assert(selected, "no worktree selected")
	editor.open(tostring(selected.worktree.path), deps.runner, deps.homeDirectory)
end

local function execute(args: { string }, options: Dependencies?)
	local command, trailing = route(args)
	local deps = dependencies(options)

	if command == "help" then
		deps.write(HELP)
	elseif command == "to" then
		to(deps, trailing)
	elseif command == "list" then
		list(deps, listOptions(trailing))
	elseif command == "recent" then
		local selectedOptions = recentOptions(trailing)
		local items = filteredRecent(recentItems(deps.loadSessions(), deps.loadWorktrees()), selectedOptions)
		attachPullRequests(items, deps.runner)
		if selectedOptions.json then
			local values: { json.Value } = {}
			for _, item in items do
				table.insert(values, itemJson(item))
			end
			deps.write(json.serialize(values, true))
		else
			deps.write(render.numbered(items))
		end
	elseif command == "cursor" then
		local cursorItems: { RecentItem } = {}
		for _, item in recentItems(deps.loadSessions(), deps.loadWorktrees()) do
			if item.session.agent == "cursor" then
				table.insert(cursorItems, item)
			end
		end
		local selected = selectItem(cursorItems, trailing[1], deps.input, deps.write)
		assert(selected, "no matching Cursor session found")
		local target = assert(itemWorktree(selected), "Cursor session has no workspace")
		editor.resume(tostring(target.path), selected.session.id, deps.runner)
	end
end

-- Lute passes the program path as the first argument.
local function run(argv: { string })
	local ok, message = pcall(execute, { table.unpack(argv, 2) }, nil)
	if not ok then
		print(`Error: {message}`)
		process.exit(1)
	end
end

return table.freeze({
	execute = execute,
	listOptions = listOptions,
	recentOptions = recentOptions,
	route = route,
	run = run,
})
