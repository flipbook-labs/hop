local batteriesCli = require("@batteries/cli")
local io = require("@std/io")
local json = require("@std/json")
local path = require("@std/path")
local process = require("@std/process")

local Claude = require("@root/providers/claude")
local Cursor = require("@root/providers/cursor")
local defaultRun = require("@root/command")
local editor = require("@root/editor")
local git = require("@root/git")
local github = require("@root/github")
local loadConfig = require("@root/config/load")
local matchWorktrees = require("@root/core/matchWorktrees")
local providers = require("@root/providers")
local render = require("@root/render")
local types = require("@root/types")

type RecentItem = render.RecentItem

export type Dependencies = {
	runner: types.CommandRunner?,
	input: (() -> string?)?,
	write: ((string) -> ())?,
	homeDirectory: path.Pathlike?,
	loadSessions: (() -> { types.Session })?,
	loadWorktrees: (() -> { types.Worktree })?,
}

type RecentOptions = {
	limit: number,
	repository: string?,
	agent: string?,
	json: boolean,
}

local COMMANDS: { [string]: boolean } = {
	recent = true,
	go = true,
	pr = true,
	cursor = true,
	help = true,
}

local HELP = [[
hop — jump from agent sessions and pull requests to local worktrees

USAGE:
  hop recent [--limit N] [--repo OWNER/REPO] [--agent cursor|claude] [--json]
  hop go [NUMBER|QUERY]
  hop pr <URL|NUMBER>
  hop cursor [NUMBER|QUERY]
  hop help
]]

local function findCommand(args: { string }): (string, { string })
	for index, value in args do
		if COMMANDS[value] then
			local trailing: { string } = {}
			for trailingIndex = index + 1, #args do
				table.insert(trailing, args[trailingIndex])
			end
			return value, trailing
		end
	end
	return "help", {}
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

local function dependencies(options: Dependencies?): (types.CommandRunner, () -> string?, (string) -> (), () -> { types.Worktree }, (
) -> { types.Session })
	local resolved: Dependencies = options or {}
	local runner = resolved.runner or defaultRun
	local input = resolved.input or function()
		return io.input()
	end
	local write = resolved.write or print
	local home = resolved.homeDirectory or process.homedir()
	local loadWorktrees = resolved.loadWorktrees
		or function()
			local config = loadConfig({ homeDirectory = home })
			return git.discover(config.roots, { runner = runner })
		end
	local loadSessions = resolved.loadSessions
		or function()
			return providers.collect({
				Cursor.new({ homeDirectory = home, runner = runner }),
				Claude.new({ homeDirectory = home }),
			})
		end
	return runner, input, write, loadWorktrees, loadSessions
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
	local repositories: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, item in items do
		local repository = if item.worktree then item.worktree.repository else nil
		if repository and not seen[repository] then
			seen[repository] = true
			table.insert(repositories, repository)
		end
	end
	local pullRequests = github.listOpenPullRequests(repositories, runner)
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

local function chooseWorktree(
	worktrees: { types.Worktree },
	input: () -> string?,
	write: (string) -> ()
): types.Worktree?
	if #worktrees == 0 then
		return nil
	elseif #worktrees == 1 then
		return worktrees[1]
	end
	for index, worktree in worktrees do
		write(`{index}. {worktree.path} · {worktree.branch or "detached"}`)
	end
	write("Choose a number:")
	local selected = tonumber(input())
	if selected == nil or selected % 1 ~= 0 or worktrees[selected] == nil then
		error("selection must be one of the listed numbers")
	end
	return worktrees[selected]
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

local function execute(args: { string }, options: Dependencies?)
	local command, trailing = findCommand(args)
	local runner, input, write, loadWorktrees, loadSessions = dependencies(options)

	if command == "help" then
		write(HELP)
		return
	end

	local worktrees = loadWorktrees()
	if command == "recent" then
		local selectedOptions = recentOptions(trailing)
		local items = filteredRecent(recentItems(loadSessions(), worktrees), selectedOptions)
		attachPullRequests(items, runner)
		if selectedOptions.json then
			local values: { json.Value } = {}
			for _, item in items do
				table.insert(values, itemJson(item))
			end
			write(json.serialize(values, true))
		else
			write(render.numbered(items))
		end
	elseif command == "go" then
		local query = trailing[1]
		local items = recentItems(loadSessions(), worktrees)
		local selectedItem = selectItem(items, query, input, write)
		local target = if selectedItem then itemWorktree(selectedItem) else nil
		if target == nil and query then
			target = chooseWorktree(matchWorktrees(worktrees, query), input, write)
		end
		assert(target, "no matching worktree found")
		editor.open(tostring(target.path), runner)
	elseif command == "pr" then
		local value = assert(trailing[1], "PR number or URL is required")
		local repositories: { string } = {}
		local seenRepositories: { [string]: boolean } = {}
		for _, worktree in worktrees do
			if worktree.repository and not seenRepositories[worktree.repository] then
				seenRepositories[worktree.repository] = true
				table.insert(repositories, worktree.repository)
			end
		end
		local pullRequest = github.resolvePullRequest(value, runner, repositories)
		local branchMatches = matchWorktrees(worktrees, pullRequest.branch)
		local repositoryMatches: { types.Worktree } = {}
		for _, worktree in branchMatches do
			if worktree.repository == pullRequest.repository then
				table.insert(repositoryMatches, worktree)
			end
		end
		local target = chooseWorktree(repositoryMatches, input, write)
		assert(target, `no worktree exists for {pullRequest.repository}:{pullRequest.branch}`)
		editor.open(tostring(target.path), runner)
	elseif command == "cursor" then
		local cursorItems: { RecentItem } = {}
		for _, item in recentItems(loadSessions(), worktrees) do
			if item.session.agent == "cursor" then
				table.insert(cursorItems, item)
			end
		end
		local selected = selectItem(cursorItems, trailing[1], input, write)
		assert(selected, "no matching Cursor session found")
		local target = assert(itemWorktree(selected), "Cursor session has no workspace")
		editor.resume(tostring(target.path), selected.session.id, runner)
	end
end

local function run(args: { string })
	local ok, message = pcall(execute, args, nil)
	if not ok then
		print(`Error: {message}`)
		process.exit(1)
	end
end

return table.freeze({
	execute = execute,
	findCommand = findCommand,
	recentOptions = recentOptions,
	run = run,
})
