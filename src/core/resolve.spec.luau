local fs = require("@std/fs")
local json = require("@std/json")
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
	assert.eq(resolve.parse("7").kind, "query")
	assert.eq(resolve.parse("feat/new-story-api").kind, "query")
	assert.eq(resolve.parse("story loading").kind, "query")
end)

-- The VS Code extension's parser runs the same cases, so `hop <expr>` and Hop: Go agree.
test.case("resolve parses the shared expression cases", function(assert)
	local cases = json.asArray(json.deserialize(fs.readFileToString("src/core/expressions.json")))
		or error("expected an array of cases")
	for _, value in cases do
		local case = json.asObject(value) or error("expected a case object")
		local input = case.input
		assert.eq(type(input), "string")
		local expression = resolve.parse(input :: string)
		local reference = json.asObject(case.reference)
		if reference == nil then
			assert.eq(expression.kind, "query")
		elseif expression.kind == "pullRequest" then
			assert.eq(expression.number, reference.number)
			assert.eq(expression.repository, reference.repository)
			assert.eq(expression.repositoryName, reference.repositoryName)
		else
			error(`expected a PR reference for {input}`)
		end
	end
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

test.case("an exact branch name lists worktrees on that branch first without hiding other matches", function(assert)
	local value = snapshot.build({
		worktree("/src/hop", "main", "org/hop", "main", true),
		worktree("/src/hop-hop", "hop", "org/hop", "main"),
		worktree("/src/hop-feature", "feature", "org/hop", "main"),
	}, {}, 0)
	local result: { string } = {}
	for _, entry in resolve.resolve(value, resolve.parse("hop"), activity).entries do
		table.insert(result, tostring(entry.worktree.path))
	end
	assert.eq(#result, 3)
	assert.eq(result[1], "/src/hop-hop")
	assert.eq(result[2], "/src/hop")
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

local function otherEntry(directory: string, repository: string, number: number, branch: string): snapshot.Entry
	return {
		worktree = worktree(directory, branch, repository),
		pullRequest = {
			number = number,
			url = `https://github.com/{repository}/pull/{number}`,
			branch = branch,
			repository = repository,
			author = "alberto",
		},
	}
end

local otherEntries: { snapshot.Entry } = {
	otherEntry("/cache/worktrees/org/apps-pr-7", "org/apps", 7, "alberto/fonts"),
	otherEntry("/cache/worktrees/org/design-pr-3", "org/design", 3, "pr-3"),
}

local function checkoutTarget(value: snapshot.Snapshot, text: string): resolve.CheckoutTarget?
	return resolve.checkoutTarget(value, resolve.parse(text), otherEntries)
end

test.case("a PR reference names the repository to look it up in", function(assert)
	local value = snapshot.build(worktrees, {}, 0)

	local url = checkoutTarget(value, "https://github.com/Other/thing/pull/5") or error("expected a target")
	assert.eq(url.repository, "Other/thing")
	assert.eq(url.number, 5)

	local named = checkoutTarget(value, "uiblox#12") or error("expected a target")
	assert.eq(named.repository, "org/uiblox")
	assert.eq(named.number, 12)

	local cloned = checkoutTarget(value, "design#4") or error("expected a target")
	assert.eq(cloned.repository, "org/design")

	assert.eq(checkoutTarget(value, "#12"), nil)
	assert.eq(checkoutTarget(value, "missing#12"), nil)
	assert.eq(checkoutTarget(value, "uiblox"), nil)
end)

local function otherPaths(text: string): { string }
	local result: { string } = {}
	for _, entry in resolve.resolveOthers(otherEntries, resolve.parse(text)) do
		table.insert(result, tostring(entry.worktree.path))
	end
	return result
end

test.case("others' work is reached by PR reference but never by search words", function(assert)
	assert.eq(otherPaths("#7")[1], "/cache/worktrees/org/apps-pr-7")
	assert.eq(otherPaths("apps#7")[1], "/cache/worktrees/org/apps-pr-7")
	assert.eq(otherPaths("https://github.com/Org/Apps/pull/7")[1], "/cache/worktrees/org/apps-pr-7")
	assert.eq(#otherPaths("uiblox#7"), 0)
	assert.eq(#otherPaths("fonts"), 0)
	assert.eq(#otherPaths("apps"), 0)
end)
