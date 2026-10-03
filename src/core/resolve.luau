local matchWorktrees = require("@root/core/matchWorktrees")
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

local function titleMatches(pullRequest: types.PullRequest?, text: string): boolean
	return pullRequest ~= nil and pullRequest.title ~= nil and pullRequest.title:lower():find(text, 1, true) ~= nil
end

local function resolveQuery(value: snapshot.Snapshot, text: string): Resolution
	local byPath: { [string]: snapshot.Entry } = {}
	local worktrees: { types.Worktree } = {}
	for _, entry in value.entries do
		byPath[tostring(entry.worktree.path)] = entry
		table.insert(worktrees, entry.worktree)
	end

	local entries: { snapshot.Entry } = {}
	local included: { [snapshot.Entry]: boolean } = {}
	for _, worktree in matchWorktrees(worktrees, text) do
		local entry = byPath[tostring(worktree.path)]
		if entry and not included[entry] then
			included[entry] = true
			table.insert(entries, entry)
		end
	end

	local normalized = text:lower()
	for _, entry in value.entries do
		if not included[entry] and titleMatches(entry.pullRequest, normalized) then
			included[entry] = true
			table.insert(entries, entry)
		end
	end

	local pullRequests: { types.PullRequest } = {}
	for _, pullRequest in value.pullRequests do
		if titleMatches(pullRequest, normalized) then
			table.insert(pullRequests, pullRequest)
		end
	end
	return { entries = entries, pullRequests = pullRequests }
end

local function resolve(value: snapshot.Snapshot, expression: Expression): Resolution
	if expression.kind == "pullRequest" then
		return resolvePullRequest(value, expression)
	end
	return resolveQuery(value, expression.text)
end

return table.freeze({
	parse = parse,
	resolve = resolve,
})
