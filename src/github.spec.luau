local test = require("@std/test")

local github = require("@root/github")
local types = require("@root/types")

local function result(ok: boolean, stdout: string, stderr: string): types.CommandResult
	return { ok = ok, exitCode = if ok then 0 else 1, stdout = stdout, stderr = stderr }
end

test.case("GitHub lists pull requests of every state for each repository", function(assert)
	local observed: { string } = {}
	local pullRequests = github.listPullRequests({ "example/widgets" }, function(argv)
		observed = argv
		return result(
			true,
			'[{"number":42,"title":"Add hop","headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42","state":"OPEN","isDraft":true}]',
			""
		)
	end)
	assert.eq(observed[1], "gh")
	assert.eq(observed[5], "example/widgets")
	assert.eq(observed[7], "all")
	assert.eq(#pullRequests, 1)
	assert.eq(pullRequests[1].title, "Add hop")
	assert.eq(pullRequests[1].state, "OPEN")
	assert.eq(pullRequests[1].draft, true)
	assert.eq(pullRequests[1].repository, "example/widgets")
end)

test.case("GitHub skips repositories when gh fails", function(assert)
	local pullRequests = github.listPullRequests({ "example/widgets" }, function()
		return result(false, "", "not authenticated")
	end)
	assert.eq(#pullRequests, 0)
end)

test.case("GitHub indexes by branch and prefers open, then newest, pull requests", function(assert)
	local function pullRequest(number: number, state: string): types.PullRequest
		return {
			number = number,
			url = `https://github.com/example/widgets/pull/{number}`,
			branch = "feature/hop",
			repository = "example/widgets",
			state = state,
		}
	end
	local index = github.indexPullRequests({
		pullRequest(10, "MERGED"),
		pullRequest(12, "OPEN"),
		pullRequest(15, "CLOSED"),
	})
	local selected = index[github.pullRequestKey("example/widgets", "feature/hop")] or error("expected pull request")
	assert.eq(selected.number, 12)

	local closed = github.indexPullRequests({ pullRequest(3, "CLOSED"), pullRequest(7, "CLOSED") })
	local newest = closed[github.pullRequestKey("example/widgets", "feature/hop")] or error("expected pull request")
	assert.eq(newest.number, 7)
end)
