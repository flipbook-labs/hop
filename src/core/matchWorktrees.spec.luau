local path = require("@std/path")
local test = require("@std/test")

local matchWorktrees = require("@root/core/matchWorktrees")
local types = require("@root/types")

local worktrees: { types.Worktree } = {
	{ path = path.parse("/src/repo-main"), branch = "main", repository = "org/repo", primary = true },
	{
		path = path.parse("/src/repo-feature"),
		branch = "feature/navigation",
		repository = "org/repo",
		primary = false,
	},
	{ path = path.parse("/src/other"), branch = "feature/other", repository = "org/other", primary = true },
}

test.case("an exact branch match short-circuits lower-ranked matches", function(assert)
	local matches = matchWorktrees(worktrees, "main")
	assert.eq(#matches, 1)
	assert.eq(tostring(matches[1].path), "/src/repo-main")
end)

test.case("matching ranks branch before basename before repository", function(assert)
	local branch = matchWorktrees(worktrees, "navigation")
	assert.eq(tostring(branch[1].path), "/src/repo-feature")
	local basename = matchWorktrees(worktrees, "repo-feature")
	assert.eq(tostring(basename[1].path), "/src/repo-feature")
	local repository = matchWorktrees(worktrees, "org/other")
	assert.eq(tostring(repository[1].path), "/src/other")
end)

test.case("matching always returns a target set", function(assert)
	assert.eq(#matchWorktrees(worktrees, "missing"), 0)
end)
