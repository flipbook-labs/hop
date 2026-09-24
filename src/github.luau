local json = require("@std/json")
local task = require("@std/task")

local defaultRun = require("@root/command")
local types = require("@root/types")

export type PullRequest = types.PullRequest

local BATCH_SIZE = 10
local CONCURRENCY = 5
local PULL_REQUEST_FIELDS =
	"pullRequests(first: 100, orderBy: {field: CREATED_AT, direction: DESC}) { nodes { number title url headRefName state isDraft } }"

local STATE_RANK: { [string]: number } = {
	OPEN = 3,
	MERGED = 2,
	CLOSED = 1,
}

local function pullRequestKey(repository: string, branch: string): string
	return `{repository}\0{branch}`
end

local function parsePullRequest(value: json.Value, repository: string): PullRequest?
	local object = json.asObject(value)
	if object == nil then
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

local function batchCommand(batch: { string }): { string }
	local declarations: { string } = {}
	local selections: { string } = {}
	local argv = { "gh", "api", "graphql" }
	for index, repository in batch do
		local owner, name = repository:match("^([^/]+)/([^/]+)$")
		table.insert(declarations, `$owner{index}: String!, $name{index}: String!`)
		table.insert(
			selections,
			`repository{index}: repository(owner: $owner{index}, name: $name{index}) \{ {PULL_REQUEST_FIELDS} }`
		)
		table.insert(argv, "-f")
		table.insert(argv, `owner{index}={owner or ""}`)
		table.insert(argv, "-f")
		table.insert(argv, `name{index}={name or ""}`)
	end
	table.insert(argv, "-f")
	table.insert(argv, `query=query({table.concat(declarations, ", ")}) \{ {table.concat(selections, " ")} }`)
	return argv
end

-- gh exits non-zero when any repository in a batch fails but still prints the others' data.
local function fetchBatch(batch: { string }, run: types.CommandRunner): { PullRequest }
	local result: { PullRequest } = {}
	local ok, response = pcall(run, batchCommand(batch))
	if not ok then
		return result
	end
	local decodedOk, decoded = pcall(json.deserialize, response.stdout)
	local body = if decodedOk then json.asObject(decoded) else nil
	local data = if body then json.asObject(body.data) else nil
	if data == nil then
		return result
	end
	for index, repository in batch do
		local repositoryObject = json.asObject(data[`repository{index}`])
		local connection = if repositoryObject then json.asObject(repositoryObject.pullRequests) else nil
		local nodes = if connection then json.asArray(connection.nodes) else nil
		for _, value in nodes or {} do
			local pullRequest = parsePullRequest(value, repository)
			if pullRequest then
				table.insert(result, pullRequest)
			end
		end
	end
	return result
end

-- Batches share one GraphQL request each and run concurrently, since each gh call costs about a second.
local function listPullRequests(repositories: { string }, runner: types.CommandRunner?): { PullRequest }
	local run = runner or defaultRun
	local batches: { { string } } = {}
	for start = 1, #repositories, BATCH_SIZE do
		table.insert(batches, { table.unpack(repositories, start, math.min(start + BATCH_SIZE - 1, #repositories)) })
	end

	local results: { { PullRequest } } = {}
	local nextBatch = 1
	local active = 0
	local function work()
		while nextBatch <= #batches do
			local index = nextBatch
			nextBatch += 1
			results[index] = fetchBatch(batches[index], run)
		end
		active -= 1
	end
	for _ = 1, math.min(CONCURRENCY, #batches) do
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
