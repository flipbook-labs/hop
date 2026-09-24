local json = require("@std/json")
local path = require("@std/path")

local github = require("@root/github")
local types = require("@root/types")

export type Entry = {
	worktree: types.Worktree,
	pullRequest: types.PullRequest?,
}

-- Everything Hop knows about local work at one moment: every worktree with its
-- associated PR, plus open PRs that have no local worktree yet.
export type Snapshot = {
	generatedAt: number,
	entries: { Entry },
	pullRequests: { types.PullRequest },
}

local function repositories(worktrees: { types.Worktree }): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, worktree in worktrees do
		local repository = worktree.repository
		if repository and not seen[repository] then
			seen[repository] = true
			table.insert(result, repository)
		end
	end
	return result
end

local function build(worktrees: { types.Worktree }, pullRequests: { types.PullRequest }, generatedAt: number): Snapshot
	local index = github.indexPullRequests(pullRequests)
	local used: { [string]: boolean } = {}
	local entries: { Entry } = {}
	for _, worktree in worktrees do
		local pullRequest: types.PullRequest? = nil
		if worktree.repository and worktree.branch then
			local key = github.pullRequestKey(worktree.repository, worktree.branch)
			pullRequest = index[key]
			used[key] = true
		end
		table.insert(entries, { worktree = worktree, pullRequest = pullRequest })
	end

	local unmatched: { types.PullRequest } = {}
	for key, pullRequest in index do
		if not used[key] and pullRequest.state == "OPEN" then
			table.insert(unmatched, pullRequest)
		end
	end
	table.sort(unmatched, function(left: types.PullRequest, right: types.PullRequest)
		if left.repository == right.repository then
			return left.number > right.number
		end
		return left.repository < right.repository
	end)
	return { generatedAt = generatedAt, entries = entries, pullRequests = unmatched }
end

local function repositoryName(worktree: types.Worktree): string
	if worktree.repository then
		return worktree.repository:match("/(.+)$") or worktree.repository
	end
	local root = worktree.root or tostring(worktree.path)
	return root:gsub("/+$", ""):match("([^/]+)$") or root
end

-- Repositories without an `origin/HEAD` fall back to the conventional default branch names.
local function isDefaultBranch(worktree: types.Worktree): boolean
	local branch = worktree.branch
	if branch == nil then
		return false
	elseif worktree.defaultBranch then
		return branch == worktree.defaultBranch
	end
	return branch == "main" or branch == "master"
end

local function pullRequestJson(pullRequest: types.PullRequest): json.Object
	return {
		repository = pullRequest.repository,
		number = pullRequest.number,
		title = pullRequest.title,
		url = pullRequest.url,
		branch = pullRequest.branch,
		state = pullRequest.state,
		draft = pullRequest.draft,
	}
end

local function toJson(snapshot: Snapshot): json.Object
	local worktrees: json.Array = {}
	for _, entry in snapshot.entries do
		local worktree = entry.worktree
		local repository: json.Object = {
			name = repositoryName(worktree),
			root = worktree.root,
			remote = worktree.repository,
			defaultBranch = worktree.defaultBranch,
		}
		local item: json.Object = {
			repository = repository,
			path = tostring(worktree.path),
			branch = worktree.branch,
			head = worktree.head,
			primary = worktree.primary,
			pr = if entry.pullRequest then pullRequestJson(entry.pullRequest) else nil,
		}
		table.insert(worktrees, item)
	end
	local pullRequests: json.Array = {}
	for _, pullRequest in snapshot.pullRequests do
		table.insert(pullRequests, pullRequestJson(pullRequest))
	end
	return {
		generatedAt = snapshot.generatedAt,
		worktrees = worktrees,
		pullRequests = pullRequests,
	}
end

local function optionalString(value: json.Value): string?
	return if type(value) == "string" then value else nil
end

local function pullRequestFromJson(value: json.Value): types.PullRequest?
	local object = json.asObject(value)
	if object == nil then
		return nil
	end
	local number = object.number
	local url = object.url
	local branch = object.branch
	local repository = object.repository
	if
		type(number) ~= "number"
		or type(url) ~= "string"
		or type(branch) ~= "string"
		or type(repository) ~= "string"
	then
		return nil
	end
	local draft = object.draft
	return {
		number = number,
		url = url,
		branch = branch,
		repository = repository,
		title = optionalString(object.title),
		state = optionalString(object.state),
		draft = if type(draft) == "boolean" then draft else nil,
	}
end

-- Returns nil for anything that is not a snapshot this version of Hop wrote.
local function fromJson(value: json.Value): Snapshot?
	local object = json.asObject(value)
	if object == nil then
		return nil
	end
	local generatedAt = object.generatedAt
	local worktrees = json.asArray(object.worktrees)
	local pullRequests = json.asArray(object.pullRequests)
	if type(generatedAt) ~= "number" or worktrees == nil or pullRequests == nil then
		return nil
	end

	local entries: { Entry } = {}
	for _, item in worktrees do
		local worktreeObject = json.asObject(item)
		local worktreePath = if worktreeObject then worktreeObject.path else nil
		if worktreeObject == nil or type(worktreePath) ~= "string" then
			return nil
		end
		local repository: json.Object = json.asObject(worktreeObject.repository) or {}
		table.insert(entries, {
			worktree = {
				path = path.parse(worktreePath),
				branch = optionalString(worktreeObject.branch),
				repository = optionalString(repository.remote),
				root = optionalString(repository.root),
				head = optionalString(worktreeObject.head),
				defaultBranch = optionalString(repository.defaultBranch),
				primary = worktreeObject.primary == true,
			},
			pullRequest = pullRequestFromJson(worktreeObject.pr),
		})
	end

	local unmatched: { types.PullRequest } = {}
	for _, item in pullRequests do
		local pullRequest = pullRequestFromJson(item)
		if pullRequest then
			table.insert(unmatched, pullRequest)
		end
	end
	return { generatedAt = generatedAt, entries = entries, pullRequests = unmatched }
end

return table.freeze({
	build = build,
	fromJson = fromJson,
	isDefaultBranch = isDefaultBranch,
	repositories = repositories,
	repositoryName = repositoryName,
	toJson = toJson,
})
