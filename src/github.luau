local json = require("@std/json")

local defaultRun = require("@root/command")
local types = require("@root/types")

export type PullRequest = types.PullRequest

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

local function listPullRequests(repositories: { string }, runner: types.CommandRunner?): { PullRequest }
	local run = runner or defaultRun
	local result: { PullRequest } = {}
	for _, repository in repositories do
		local ok, response = pcall(run, {
			"gh",
			"pr",
			"list",
			"--repo",
			repository,
			"--state",
			"all",
			"--limit",
			"100",
			"--json",
			"number,title,url,headRefName,state,isDraft",
		})
		if not ok or not response.ok then
			continue
		end
		local decodedOk, decoded = pcall(json.deserialize, response.stdout)
		local values = if decodedOk then json.asArray(decoded) else nil
		for _, value in values or {} do
			local pullRequest = parsePullRequest(value, repository)
			if pullRequest then
				table.insert(result, pullRequest)
			end
		end
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
