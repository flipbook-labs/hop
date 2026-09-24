local test = require("@std/test")

local github = require("@root/github")
local types = require("@root/types")

local function result(ok: boolean, stdout: string, stderr: string): types.CommandResult
	return { ok = ok, exitCode = if ok then 0 else 1, stdout = stdout, stderr = stderr }
end

local PULL_REQUEST =
	'{"number":42,"title":"Add hop","headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42","state":"OPEN","isDraft":true}'

local function hasArgument(argv: { string }, value: string): boolean
	return table.find(argv, value) ~= nil
end

test.case("GitHub lists pull requests of every state for each repository", function(assert)
	local observed: { string } = {}
	local pullRequests = github.listPullRequests({ "example/widgets" }, function(argv)
		observed = argv
		return result(true, `\{"data":\{"repository1":\{"pullRequests":\{"nodes":[{PULL_REQUEST}]}}}}`, "")
	end)
	assert.eq(observed[1], "gh")
	assert.eq(observed[2], "api")
	assert.eq(observed[3], "graphql")
	assert.eq(hasArgument(observed, "owner1=example"), true)
	assert.eq(hasArgument(observed, "name1=widgets"), true)
	assert.eq(#pullRequests, 1)
	assert.eq(pullRequests[1].title, "Add hop")
	assert.eq(pullRequests[1].state, "OPEN")
	assert.eq(pullRequests[1].draft, true)
	assert.eq(pullRequests[1].repository, "example/widgets")
end)

test.case("GitHub batches repositories into shared requests", function(assert)
	local repositories: { string } = {}
	for index = 1, 25 do
		table.insert(repositories, `example/repo{index}`)
	end
	local calls = 0
	local lastBatch: { string } = {}
	github.listPullRequests(repositories, function(argv)
		calls += 1
		lastBatch = argv
		return result(true, '{"data":{}}', "")
	end)
	assert.eq(calls, 3)
	assert.eq(hasArgument(lastBatch, "name5=repo25"), true)
	assert.eq(hasArgument(lastBatch, "name6=repo26"), false)
end)

test.case("GitHub keeps repositories that resolved when others in the batch fail", function(assert)
	local pullRequests = github.listPullRequests({ "example/widgets", "example/missing" }, function()
		return result(
			false,
			`\{"data":\{"repository1":\{"pullRequests":\{"nodes":[{PULL_REQUEST}]}},"repository2":null},"errors":[]}`,
			"Could not resolve to a Repository"
		)
	end)
	assert.eq(#pullRequests, 1)
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
