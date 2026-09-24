local test = require("@std/test")

local github = require("@root/github")
local types = require("@root/types")

local function result(ok: boolean, stdout: string, stderr: string): types.CommandResult
	return { ok = ok, exitCode = if ok then 0 else 1, stdout = stdout, stderr = stderr }
end

test.case("GitHub resolves a PR URL to its repository and head branch", function(assert)
	local observed: { string } = {}
	local pullRequest = github.resolvePullRequest("https://github.com/example/widgets/pull/42", function(argv)
		observed = argv
		return result(
			true,
			'{"number":42,"url":"https://github.com/example/widgets/pull/42","headRefName":"feature/hop","headRepository":{"nameWithOwner":"example/widgets"}}',
			""
		)
	end)
	assert.eq(observed[1], "gh")
	assert.eq(observed[4], "https://github.com/example/widgets/pull/42")
	assert.eq(pullRequest.branch, "feature/hop")
	assert.eq(pullRequest.repository, "example/widgets")
end)

test.case("GitHub accepts PR numbers", function(assert)
	local pullRequest = github.resolvePullRequest("7", function()
		return result(
			true,
			'{"number":7,"url":"https://github.com/org/repo/pull/7","headRefName":"fix","headRepository":{"nameWithOwner":"org/repo"}}',
			""
		)
	end)
	assert.eq(pullRequest.branch, "fix")
end)

test.case("GitHub resolves PR numbers across configured repository owners", function(assert)
	local calls = 0
	local pullRequest = github.resolvePullRequest("42", function(argv)
		calls += 1
		if argv[2] == "search" then
			return result(
				true,
				'[{"number":42,"url":"https://github.com/example/widgets/pull/42","repository":{"nameWithOwner":"example/widgets"}}]',
				""
			)
		end
		return result(
			true,
			'{"number":42,"url":"https://github.com/example/widgets/pull/42","headRefName":"feature/hop","headRepository":{"nameWithOwner":"example/widgets"}}',
			""
		)
	end, { "example/widgets" })
	assert.eq(calls, 2)
	assert.eq(pullRequest.repository, "example/widgets")
end)

test.case("GitHub indexes open pull requests by repository and branch", function(assert)
	local pullRequests = github.listOpenPullRequests({ "example/widgets" }, function()
		return result(
			true,
			'[{"number":42,"headRefName":"feature/hop","url":"https://github.com/example/widgets/pull/42"}]',
			""
		)
	end)
	local pullRequest = pullRequests[github.pullRequestKey("example/widgets", "feature/hop")]
		or error("expected pull request")
	assert.eq(pullRequest.number, 42)
	assert.eq(pullRequest.url, "https://github.com/example/widgets/pull/42")
end)

test.case("GitHub reports gh failures clearly", function(assert)
	local ok, message = pcall(github.resolvePullRequest, "7", function()
		return result(false, "", "not authenticated")
	end, nil)
	assert.eq(ok, false)
	assert.strContains(tostring(message), "not authenticated")
end)
