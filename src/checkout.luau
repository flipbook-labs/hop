local fs = require("@std/fs")
local path = require("@std/path")

local git = require("@root/git")
local github = require("@root/github")
local resolve = require("@root/core/resolve")
local snapshot = require("@root/core/snapshot")
local types = require("@root/types")

export type Result = {
	entry: snapshot.Entry,
	created: boolean,
}

local function sameRepository(left: string?, right: string): boolean
	return left ~= nil and left:lower() == right:lower()
end

-- Any worktree of the repository knows its primary checkout's path, so prefer the primary but accept any.
local function checkoutOf(value: snapshot.Snapshot, repository: string): types.Worktree?
	local found: types.Worktree? = nil
	for _, entry in value.entries do
		local worktree = entry.worktree
		if sameRepository(worktree.repository, repository) then
			if worktree.primary then
				return worktree
			end
			found = found or worktree
		end
	end
	return found
end

local function removePullRequest(value: snapshot.Snapshot, pullRequest: types.PullRequest)
	for index = #value.pullRequests, 1, -1 do
		local candidate = value.pullRequests[index]
		if candidate.number == pullRequest.number and sameRepository(candidate.repository, pullRequest.repository) then
			table.remove(value.pullRequests, index)
		end
	end
end

-- Fork PRs get a local branch named after the PR, since their head branch name belongs to the fork.
local function localBranch(pullRequest: types.PullRequest, crossRepository: boolean): string
	return if crossRepository then `pr-{pullRequest.number}` else pullRequest.branch
end

-- Opens a PR without a worktree. A worktree already on the PR's branch is reused; otherwise a new
-- one is added beside the repository's primary checkout as `<primary>-pr-<number>`. The snapshot is
-- updated in place so it can be cached.
local function pullRequest(
	value: snapshot.Snapshot,
	target: resolve.CheckoutTarget,
	runner: types.CommandRunner?
): Result
	local primary = checkoutOf(value, target.repository)
	if primary == nil or primary.repository == nil then
		error(`no local clone of {target.repository} was found; clone it under one of Hop's roots first`, 0)
	end
	local repository = primary.repository
	local details, crossRepository = github.viewPullRequest(repository, target.number, runner)
	local branch = localBranch(details, crossRepository)

	-- A same-repository PR's head is its branch, so a worktree on that branch already holds this PR's code
	-- even when the cache links it to another open PR from the same branch. Fork PRs use `pr-<number>`.
	for _, entry in value.entries do
		if entry.worktree.branch == branch and sameRepository(entry.worktree.repository, repository) then
			entry.pullRequest = entry.pullRequest or details
			removePullRequest(value, details)
			return { entry = entry, created = false }
		end
	end

	local root = primary.root or tostring(primary.path)
	local destination = path.join(path.dirname(root), `{path.basename(root)}-pr-{details.number}`)
	if fs.exists(destination) then
		error(`{destination} already exists but is not on {branch}`, 0)
	end
	git.addPullRequestWorktree({
		primary = root,
		path = tostring(destination),
		number = details.number,
		branch = branch,
		crossRepository = crossRepository,
	}, runner)

	local entry: snapshot.Entry = {
		worktree = {
			path = destination,
			branch = branch,
			repository = repository,
			root = root,
			head = nil,
			defaultBranch = primary.defaultBranch,
			primary = false,
		},
		pullRequest = details,
	}
	table.insert(value.entries, entry)
	removePullRequest(value, details)
	return { entry = entry, created = true }
end

return table.freeze({
	pullRequest = pullRequest,
})
