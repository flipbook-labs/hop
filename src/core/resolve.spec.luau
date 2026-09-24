local path = require("@std/path")
local test = require("@std/test")

local resolve = require("@root/core/resolve")
local snapshot = require("@root/core/snapshot")
local types = require("@root/types")

local function worktree(
	directory: string,
	branch: string,
	repository: string,
	defaultBranch: string?,
	primary: boolean?
): types.Worktree
	return {
		path = path.parse(directory),
		branch = branch,
		repository = repository,
		defaultBranch = defaultBranch,
		primary = primary == true,
	}
end

local worktrees: { types.Worktree } = {
	worktree("/src/uiblox", "master", "org/uiblox", "master", true),
	worktree("/src/uiblox-migration", "UIBLOX-1-font-migration", "org/uiblox", "master"),
	worktree("/src/uiblox-tokens", "UIBLOX-2-tokens", "org/uiblox", "master"),
	worktree("/src/apps-uiblox-update", "UIBLOX-3-update", "org/apps", "main"),
	worktree("/src/apps", "main", "org/apps", "main", true),
	worktree("/src/legacy", "master", "org/legacy", nil, true),
	worktree("/src/trunk", "develop", "org/trunk", "trunk", true),
}

local lastUsed: { [string]: number } = {
	["/src/uiblox"] = 10,
	["/src/uiblox-migration"] = 20,
	["/src/uiblox-tokens"] = 30,
	["/src/apps-uiblox-update"] = 40,
}

local function activity(value: types.Worktree): number
	return lastUsed[tostring(value.path)] or 0
end

local function paths(text: string): { string }
	local value = snapshot.build(worktrees, {}, 0)
	local result: { string } = {}
	for _, entry in resolve.resolve(value, resolve.parse(text), activity).entries do
		table.insert(result, tostring(entry.worktree.path))
	end
	return result
end

test.case("resolve parses PR expressions", function(assert)
	local full = resolve.parse("flipbook-labs/flipbook#1234")
	assert.eq(full.kind, "pullRequest")
	if full.kind == "pullRequest" then
		assert.eq(full.number, 1234)
		assert.eq(full.repository, "flipbook-labs/flipbook")
	end

	local named = resolve.parse("flipbook#12")
	if named.kind == "pullRequest" then
		assert.eq(named.repositoryName, "flipbook")
	else
		error("expected a PR expression")
	end

	local url = resolve.parse("https://github.com/flipbook-labs/hop/pull/1/files")
	if url.kind == "pullRequest" then
		assert.eq(url.repository, "flipbook-labs/hop")
		assert.eq(url.number, 1)
	else
		error("expected a PR expression")
	end

	assert.eq(resolve.parse("#7").kind, "pullRequest")
	assert.eq(resolve.parse("7").kind, "pullRequest")
	assert.eq(resolve.parse("feat/new-story-api").kind, "query")
	assert.eq(resolve.parse("story loading").kind, "query")
end)

test.case("a repository query lists its default-branch checkout first, then the most recently used", function(assert)
	local matches = paths("uiblox")
	assert.eq(#matches, 4)
	assert.eq(matches[1], "/src/uiblox")
	assert.eq(matches[2], "/src/apps-uiblox-update")
	assert.eq(matches[3], "/src/uiblox-tokens")
	assert.eq(matches[4], "/src/uiblox-migration")
end)

test.case("every query word must match", function(assert)
	local matches = paths("uiblox m")
	assert.eq(matches[1], "/src/uiblox")
	assert.eq(matches[2], "/src/uiblox-migration")
	assert.eq(#matches, 2)
	assert.eq(#paths("uiblox missing"), 0)
end)

test.case("default matches default-branch checkouts without naming the branch", function(assert)
	local uiblox = paths("uiblox default")
	assert.eq(#uiblox, 1)
	assert.eq(uiblox[1], "/src/uiblox")

	local legacy = paths("legacy default")
	assert.eq(#legacy, 1)
	assert.eq(legacy[1], "/src/legacy")

	assert.eq(#paths("trunk default"), 0)
end)

test.case("an exact branch name only returns worktrees on that branch", function(assert)
	local matches = paths("master")
	assert.eq(#matches, 2)
	assert.eq(matches[1], "/src/uiblox")
	assert.eq(matches[2], "/src/legacy")
end)

test.case("orphaned PRs match when every word is in the title", function(assert)
	local value = snapshot.build({}, {
		{
			number = 7,
			url = "https://github.com/org/apps/pull/7",
			branch = "story-loading",
			repository = "org/apps",
			title = "Speed up story loading",
			state = "OPEN",
		},
	}, 0)
	assert.eq(#resolve.resolve(value, resolve.parse("loading story")).pullRequests, 1)
	assert.eq(#resolve.resolve(value, resolve.parse("story widgets")).pullRequests, 0)
end)
