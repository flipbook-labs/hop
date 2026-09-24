local snapshot = require("@root/core/snapshot")
local types = require("@root/types")

export type Expression =
	{
		kind: "pullRequest",
		number: number,
		repository: string?,
		repositoryName: string?,
	}
	| {
		kind: "query",
		text: string,
	}

-- Worktrees the expression points at, plus matching PRs that have no local worktree.
export type Resolution = {
	entries: { snapshot.Entry },
	pullRequests: { types.PullRequest },
}

local REPOSITORY = "[%w%._%-]+/[%w%._%-]+"
local NAME = "[%w%._%-]+"

local function parse(value: string): Expression
	local trimmed = value:match("^%s*(.-)%s*$") or value
	local repository, number = trimmed:match(`^https?://github%.com/({REPOSITORY})/pull/(%d+)`)
	if repository == nil then
		repository, number = trimmed:match(`^({REPOSITORY})#(%d+)$`)
	end
	if repository and number then
		return { kind = "pullRequest", number = assert(tonumber(number)), repository = repository }
	end
	local repositoryName, nameNumber = trimmed:match(`^({NAME})#(%d+)$`)
	if repositoryName and nameNumber then
		return { kind = "pullRequest", number = assert(tonumber(nameNumber)), repositoryName = repositoryName }
	end
	local bare = trimmed:match("^#?(%d+)$")
	if bare then
		return { kind = "pullRequest", number = assert(tonumber(bare)) }
	end
	return { kind = "query", text = trimmed }
end

local function repositoryMatches(expression: Expression, repository: string): boolean
	if expression.kind ~= "pullRequest" then
		return false
	end
	local normalized = repository:lower()
	if expression.repository then
		return normalized == expression.repository:lower()
	elseif expression.repositoryName then
		return (normalized:match("/(.+)$") or normalized) == expression.repositoryName:lower()
	end
	return true
end

local function resolvePullRequest(value: snapshot.Snapshot, expression: Expression): Resolution
	assert(expression.kind == "pullRequest")
	local entries: { snapshot.Entry } = {}
	for _, entry in value.entries do
		local pullRequest = entry.pullRequest
		if
			pullRequest
			and pullRequest.number == expression.number
			and repositoryMatches(expression, pullRequest.repository)
		then
			table.insert(entries, entry)
		end
	end
	local pullRequests: { types.PullRequest } = {}
	for _, pullRequest in value.pullRequests do
		if pullRequest.number == expression.number and repositoryMatches(expression, pullRequest.repository) then
			table.insert(pullRequests, pullRequest)
		end
	end
	return { entries = entries, pullRequests = pullRequests }
end

-- Seconds since the epoch that a worktree was last used; higher sorts first.
export type Activity = (types.Worktree) -> number

-- A query word that matches worktrees on their repository's default branch.
local DEFAULT_KEYWORD = "default"

local function words(text: string): { string }
	local result: { string } = {}
	for word in text:lower():gmatch("%S+") do
		table.insert(result, word)
	end
	return result
end

local function titleMatches(pullRequest: types.PullRequest?, word: string): boolean
	return pullRequest ~= nil and pullRequest.title ~= nil and pullRequest.title:lower():find(word, 1, true) ~= nil
end

local function entryMatches(entry: snapshot.Entry, word: string): boolean
	local worktree = entry.worktree
	if word == DEFAULT_KEYWORD and snapshot.isDefaultBranch(worktree) then
		return true
	end
	local fields = {
		worktree.branch or "",
		tostring(worktree.path):match("([^/]+)/*$") or "",
		worktree.repository or "",
		snapshot.repositoryName(worktree),
	}
	for _, field in fields do
		if field:lower():find(word, 1, true) then
			return true
		end
	end
	return titleMatches(entry.pullRequest, word)
end

-- A query naming a repository puts that repository's default-branch checkout first.
local function namesDefaultCheckout(entry: snapshot.Entry, queryWords: { string }): boolean
	local worktree = entry.worktree
	if not snapshot.isDefaultBranch(worktree) then
		return false
	end
	local name = snapshot.repositoryName(worktree):lower()
	local repository = if worktree.repository then worktree.repository:lower() else nil
	for _, word in queryWords do
		if word == name or word == repository then
			return true
		end
	end
	return false
end

local function sortEntries(entries: { snapshot.Entry }, queryWords: { string }, activity: Activity)
	local pinned: { [snapshot.Entry]: boolean } = {}
	local lastUsed: { [snapshot.Entry]: number } = {}
	for _, entry in entries do
		pinned[entry] = namesDefaultCheckout(entry, queryWords)
		lastUsed[entry] = activity(entry.worktree)
	end
	table.sort(entries, function(left: snapshot.Entry, right: snapshot.Entry)
		if pinned[left] ~= pinned[right] then
			return pinned[left]
		elseif lastUsed[left] ~= lastUsed[right] then
			return lastUsed[left] > lastUsed[right]
		end
		return tostring(left.worktree.path) < tostring(right.worktree.path)
	end)
end

-- Every word must match an entry's branch, folder, repository, or PR title. A query that is
-- exactly a branch name only returns worktrees on that branch.
local function resolveQuery(value: snapshot.Snapshot, text: string, activity: Activity): Resolution
	local queryWords = words(text)
	local normalized = table.concat(queryWords, " ")

	local entries: { snapshot.Entry } = {}
	for _, entry in value.entries do
		local branch = entry.worktree.branch
		if branch and branch:lower() == normalized then
			table.insert(entries, entry)
		end
	end
	if #entries == 0 then
		for _, entry in value.entries do
			local matched = true
			for _, word in queryWords do
				if not entryMatches(entry, word) then
					matched = false
					break
				end
			end
			if matched then
				table.insert(entries, entry)
			end
		end
	end
	sortEntries(entries, queryWords, activity)

	local pullRequests: { types.PullRequest } = {}
	for _, pullRequest in value.pullRequests do
		local matched = true
		for _, word in queryWords do
			if not titleMatches(pullRequest, word) then
				matched = false
				break
			end
		end
		if matched then
			table.insert(pullRequests, pullRequest)
		end
	end
	return { entries = entries, pullRequests = pullRequests }
end

local function noActivity(_worktree: types.Worktree): number
	return 0
end

local function resolve(value: snapshot.Snapshot, expression: Expression, activity: Activity?): Resolution
	if expression.kind == "pullRequest" then
		return resolvePullRequest(value, expression)
	end
	return resolveQuery(value, expression.text, activity or noActivity)
end

return table.freeze({
	parse = parse,
	resolve = resolve,
})
