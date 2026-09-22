local json = require("@std/json")

local defaultRun = require("@root/command")
local types = require("@root/types")

export type PullRequest = types.PullRequest

local function pullRequestKey(repository: string, branch: string): string
	return `{repository}\0{branch}`
end

local function resolveNumber(value: string, repositories: { string }, runner: types.CommandRunner): string
	local repositorySet: { [string]: boolean } = {}
	local owners: { string } = {}
	local seenOwners: { [string]: boolean } = {}
	for _, repository in repositories do
		repositorySet[repository] = true
		local owner = repository:match("^([^/]+)/")
		if owner and not seenOwners[owner] then
			seenOwners[owner] = true
			table.insert(owners, owner)
		end
	end
	local matches: { string } = {}
	for _, owner in owners do
		local ok, response = pcall(runner, {
			"gh",
			"search",
			"prs",
			value,
			"--owner",
			owner,
			"--limit",
			"100",
			"--json",
			"number,url,repository",
		})
		if not ok or not response.ok then
			continue
		end
		local decodedOk, decoded = pcall(json.deserialize, response.stdout)
		local values = if decodedOk then json.asArray(decoded) else nil
		for _, candidate in values or {} do
			local object = json.asObject(candidate)
			local repositoryObject = if object then json.asObject(object.repository) else nil
			local number = if object then object.number else nil
			local url = if object then object.url else nil
			local repository = if repositoryObject then repositoryObject.nameWithOwner else nil
			if
				number == tonumber(value)
				and type(url) == "string"
				and type(repository) == "string"
				and repositorySet[repository]
			then
				table.insert(matches, url)
			end
		end
	end
	if #matches > 1 then
		error(`pull request #{value} exists in multiple local repositories; use its URL`)
	end
	return matches[1] or value
end

local function resolvePullRequest(value: string, runner: types.CommandRunner?, repositories: { string }?): PullRequest
	if not value:match("^%d+$") and not value:match("^https://github%.com/[^/]+/[^/]+/pull/%d+/?$") then
		error("pull request must be a GitHub PR number or URL")
	end
	local run = runner or defaultRun
	if value:match("^%d+$") and repositories then
		value = resolveNumber(value, repositories, run)
	end
	local ok, result = pcall(run, {
		"gh",
		"pr",
		"view",
		value,
		"--json",
		"number,headRefName,headRepository,url",
	})
	if not ok then
		error(`unable to run gh: {result}`)
	end
	if not result.ok then
		error(`gh could not resolve pull request {value}: {result.stderr}`)
	end

	local decodedOk, decoded = pcall(json.deserialize, result.stdout)
	if not decodedOk then
		error("gh returned invalid JSON")
	end
	local object = json.asObject(decoded)
	local repositoryObject = if object then json.asObject(object.headRepository) else nil
	local number = if object then object.number else nil
	local branch = if object then object.headRefName else nil
	local repository = if repositoryObject then repositoryObject.nameWithOwner else nil
	local url = if object then object.url else nil
	if
		type(number) ~= "number"
		or type(branch) ~= "string"
		or branch == ""
		or type(repository) ~= "string"
		or repository == ""
		or type(url) ~= "string"
	then
		error("gh response did not include the pull request branch and repository")
	end
	return {
		number = number,
		branch = branch,
		repository = repository,
		url = url,
	}
end

local function listOpenPullRequests(
	repositories: { string },
	runner: types.CommandRunner?
): { [string]: types.PullRequest }
	local run = runner or defaultRun
	local result: { [string]: types.PullRequest } = {}
	for _, repository in repositories do
		local ok, response = pcall(run, {
			"gh",
			"pr",
			"list",
			"--repo",
			repository,
			"--state",
			"open",
			"--limit",
			"100",
			"--json",
			"number,headRefName,url",
		})
		if not ok or not response.ok then
			continue
		end
		local decodedOk, decoded = pcall(json.deserialize, response.stdout)
		local values = if decodedOk then json.asArray(decoded) else nil
		if not values then
			continue
		end
		for _, value in values do
			local object = json.asObject(value)
			local number = if object then object.number else nil
			local branch = if object then object.headRefName else nil
			local url = if object then object.url else nil
			if type(number) == "number" and type(branch) == "string" and type(url) == "string" then
				result[pullRequestKey(repository, branch)] = {
					number = number,
					url = url,
					branch = branch,
					repository = repository,
				}
			end
		end
	end
	return result
end

return table.freeze({
	listOpenPullRequests = listOpenPullRequests,
	pullRequestKey = pullRequestKey,
	resolvePullRequest = resolvePullRequest,
})
