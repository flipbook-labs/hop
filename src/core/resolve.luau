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

local function isExactBranch(entry: snapshot.Entry, normalized: string): boolean
	local branch = entry.worktree.branch
	return branch ~= nil and branch:lower() == normalized
end

local function sortEntries(entries: { snapshot.Entry }, queryWords: { string }, activity: Activity)
	local normalized = table.concat(queryWords, " ")
	local exact: { [snapshot.Entry]: boolean } = {}
	local pinned: { [snapshot.Entry]: boolean } = {}
	local lastUsed: { [snapshot.Entry]: number } = {}
	for _, entry in entries do
		exact[entry] = isExactBranch(entry, normalized)
		pinned[entry] = namesDefaultCheckout(entry, queryWords)
		lastUsed[entry] = activity(entry.worktree)
	end
	table.sort(entries, function(left: snapshot.Entry, right: snapshot.Entry)
		if exact[left] ~= exact[right] then
			return exact[left]
		elseif pinned[left] ~= pinned[right] then
			return pinned[left]
		elseif lastUsed[left] ~= lastUsed[right] then
			return lastUsed[left] > lastUsed[right]
		end
		return tostring(left.worktree.path) < tostring(right.worktree.path)
	end)
end

-- Every word must match an entry's branch, folder, repository, or PR title. Worktrees whose branch
-- is exactly the query come first, then a named repository's default-branch checkout, then the
-- most recently changed.
local function resolveQuery(value: snapshot.Snapshot, text: string, activity: Activity): Resolution
	local queryWords = words(text)

	local entries: { snapshot.Entry } = {}
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

export type CheckoutTarget = {
	repository: string,
	number: number,
}

-- The single PR a worktree-less PR expression names, so Hop can check it out. `owner/repo#N` and
-- URLs name one outright; otherwise the PR must be the only match among known PRs or known repositories.
local function checkoutTarget(value: snapshot.Snapshot, expression: Expression, resolution: Resolution): CheckoutTarget?
	if expression.kind ~= "pullRequest" or #resolution.entries > 0 then
		return nil
	elseif expression.repository then
		return { repository = expression.repository, number = expression.number }
	elseif #resolution.pullRequests == 1 then
		return { repository = resolution.pullRequests[1].repository, number = expression.number }
	elseif #resolution.pullRequests > 1 or expression.repositoryName == nil then
		return nil
	end
	local found: string? = nil
	for _, entry in value.entries do
		local repository = entry.worktree.repository
		if repository and repositoryMatches(expression, repository) then
			if found and found:lower() ~= repository:lower() then
				return nil
			end
			found = repository
		end
	end
	return if found then { repository = found, number = expression.number } else nil
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
	checkoutTarget = checkoutTarget,
	parse = parse,
	resolve = resolve,
})
