local json = require("@std/json")
local task = require("@std/task")

local defaultRun = require("@root/command")
local types = require("@root/types")

export type PullRequest = types.PullRequest

type Lookup = {
	repository: string,
	branch: string,
}

local BATCH_SIZE = 25
local CONCURRENCY = 5
local AUTHORED_PAGES = 5
local NODE_FIELDS = "number title url headRefName state isDraft isCrossRepository"

local STATE_RANK: { [string]: number } = {
	OPEN = 3,
	MERGED = 2,
	CLOSED = 1,
}

local function pullRequestKey(repository: string, branch: string): string
	return `{repository}\0{branch}`
end

-- Fork PRs are skipped because their head branch names belong to another repository.
local function parsePullRequest(value: json.Value, repository: string): PullRequest?
	local object = json.asObject(value)
	if object == nil or object.isCrossRepository == true then
		return nil
	end
	local number = object.number
	local branch = object.headRefName
	local url = object.url
	if type(number) ~= "number" or type(branch) ~= "string" or type(url) ~= "string" then
		return nil
	end
	local title = object.title
	local state = object.state
	local draft = object.isDraft
	return {
		number = number,
		url = url,
		branch = branch,
		repository = repository,
		title = if type(title) == "string" then title else nil,
		state = if type(state) == "string" then state else nil,
		draft = if type(draft) == "boolean" then draft else nil,
	}
end

-- gh exits non-zero when part of a query fails but still prints the data that resolved.
local function query(run: types.CommandRunner, text: string, variables: { [string]: string }): json.Object?
	local names: { string } = {}
	for name in variables do
		table.insert(names, name)
	end
	table.sort(names)
	local argv = { "gh", "api", "graphql", "-f", `query={text}` }
	for _, name in names do
		table.insert(argv, "-f")
		table.insert(argv, `{name}={variables[name]}`)
	end
	local ok, response = pcall(run, argv)
	if not ok then
		return nil
	end
	local decodedOk, decoded = pcall(json.deserialize, response.stdout)
	local body = if decodedOk then json.asObject(decoded) else nil
	return if body then json.asObject(body.data) else nil
end

local function nodes(connection: json.Value): json.Array
	local object = json.asObject(connection)
	return (if object then json.asArray(object.nodes) else nil) or {}
end

-- Looks up PRs by each worktree's branch. Default branches are skipped because
-- release and sync PRs often use them as their head.
local function fetchBranches(batch: { Lookup }, run: types.CommandRunner): { PullRequest }
	local declarations: { string } = {}
	local selections: { string } = {}
	local variables: { [string]: string } = {}
	for index, lookup in batch do
		local owner, name = lookup.repository:match("^([^/]+)/([^/]+)$")
		table.insert(declarations, `$owner{index}: String!, $name{index}: String!, $branch{index}: String!`)
		table.insert(
			selections,
			`branch{index}: repository(owner: $owner{index}, name: $name{index}) \{ defaultBranchRef \{ name } `
				.. `pullRequests(headRefName: $branch{index}, first: 5, orderBy: \{field: CREATED_AT, direction: DESC}) \{ nodes \{ {NODE_FIELDS} } } }`
		)
		variables[`owner{index}`] = owner or ""
		variables[`name{index}`] = name or ""
		variables[`branch{index}`] = lookup.branch
	end

	local result: { PullRequest } = {}
	local data = query(run, `query({table.concat(declarations, ", ")}) \{ {table.concat(selections, " ")} }`, variables)
	if data == nil then
		return result
	end
	for index, lookup in batch do
		local repository = json.asObject(data[`branch{index}`])
		if repository == nil then
			continue
		end
		local defaultBranch = json.asObject(repository.defaultBranchRef)
		if defaultBranch and defaultBranch.name == lookup.branch then
			continue
		end
		for _, value in nodes(repository.pullRequests) do
			local pullRequest = parsePullRequest(value, lookup.repository)
			if pullRequest then
				table.insert(result, pullRequest)
			end
		end
	end
	return result
end

-- The viewer's open PRs in known repositories, so in-flight work without a worktree still shows up.
local function fetchAuthored(repositories: { [string]: boolean }, run: types.CommandRunner): { PullRequest }
	local result: { PullRequest } = {}
	local cursor: string? = nil
	for _ = 1, AUTHORED_PAGES do
		local variables: { [string]: string } = {}
		local declaration = ""
		local after = ""
		if cursor then
			variables.cursor = cursor
			declaration = "($cursor: String!)"
			after = ", after: $cursor"
		end
		local data = query(
			run,
			`query{declaration} \{ viewer \{ pullRequests(states: OPEN, first: 100{after}, orderBy: \{field: CREATED_AT, direction: DESC}) \{ `
				.. `pageInfo \{ hasNextPage endCursor } nodes \{ {NODE_FIELDS} repository \{ nameWithOwner } } } } }`,
			variables
		)
		local viewer = if data then json.asObject(data.viewer) else nil
		local connection = if viewer then json.asObject(viewer.pullRequests) else nil
		if connection == nil then
			break
		end
		for _, value in nodes(connection) do
			local object = json.asObject(value)
			local owner = if object then json.asObject(object.repository) else nil
			local repository = if owner then owner.nameWithOwner else nil
			if type(repository) == "string" and repositories[repository] then
				local pullRequest = parsePullRequest(value, repository)
				if pullRequest then
					table.insert(result, pullRequest)
				end
			end
		end
		local pageInfo = json.asObject(connection.pageInfo)
		local endCursor = if pageInfo then pageInfo.endCursor else nil
		if pageInfo == nil or pageInfo.hasNextPage ~= true or type(endCursor) ~= "string" then
			break
		end
		cursor = endCursor
	end
	return result
end

-- Each gh call costs about a second, so jobs share a small pool of concurrent workers.
local function runConcurrently(jobs: { () -> { PullRequest } }): { PullRequest }
	local results: { { PullRequest } } = {}
	local nextJob = 1
	local active = 0
	local function work()
		while nextJob <= #jobs do
			local index = nextJob
			nextJob += 1
			local ok, value = pcall(jobs[index])
			results[index] = if ok then value else {}
		end
		active -= 1
	end
	for _ = 1, math.min(CONCURRENCY, #jobs) do
		active += 1
		task.spawn(work)
	end
	while active > 0 do
		task.wait(0.05)
	end

	local result: { PullRequest } = {}
	for _, batch in results do
		table.move(batch, 1, #batch, #result + 1, result)
	end
	return result
end

-- PRs for the given worktrees' branches, plus the viewer's open PRs in the same repositories.
local function listPullRequests(worktrees: { types.Worktree }, runner: types.CommandRunner?): { PullRequest }
	local run = runner or defaultRun
	local repositories: { [string]: boolean } = {}
	local lookups: { Lookup } = {}
	local seen: { [string]: boolean } = {}
	for _, worktree in worktrees do
		local repository = worktree.repository
		local branch = worktree.branch
		if repository == nil then
			continue
		end
		repositories[repository] = true
		if branch and not seen[pullRequestKey(repository, branch)] then
			seen[pullRequestKey(repository, branch)] = true
			table.insert(lookups, { repository = repository, branch = branch })
		end
	end
	if next(repositories) == nil then
		return {}
	end

	local jobs: { () -> { PullRequest } } = {
		function()
			return fetchAuthored(repositories, run)
		end,
	}
	for start = 1, #lookups, BATCH_SIZE do
		local batch = { table.unpack(lookups, start, math.min(start + BATCH_SIZE - 1, #lookups)) }
		table.insert(jobs, function()
			return fetchBranches(batch, run)
		end)
	end
	return runConcurrently(jobs)
end

local function preferred(candidate: PullRequest, current: PullRequest?): boolean
	if current == nil then
		return true
	end
	local candidateRank = STATE_RANK[candidate.state or ""] or 0
	local currentRank = STATE_RANK[current.state or ""] or 0
	if candidateRank ~= currentRank then
		return candidateRank > currentRank
	end
	return candidate.number > current.number
end

-- A head branch can be reused by several PRs over time; keep the open one, then the newest.
local function indexPullRequests(pullRequests: { PullRequest }): { [string]: PullRequest }
	local result: { [string]: PullRequest } = {}
	for _, pullRequest in pullRequests do
		local key = pullRequestKey(pullRequest.repository, pullRequest.branch)
		if preferred(pullRequest, result[key]) then
			result[key] = pullRequest
		end
	end
	return result
end

return table.freeze({
	indexPullRequests = indexPullRequests,
	listPullRequests = listPullRequests,
	pullRequestKey = pullRequestKey,
})
