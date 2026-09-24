local path = require("@std/path")
local test = require("@std/test")

local github = require("@root/github")
local types = require("@root/types")

local function result(ok: boolean, stdout: string, stderr: string): types.CommandResult
	return { ok = ok, exitCode = if ok then 0 else 1, stdout = stdout, stderr = stderr }
end

local function pullRequestJson(number: number, branch: string, extra: string?): string
	return `\{"number":{number},"title":"PR {number}","headRefName":"{branch}","url":"https://github.com/example/widgets/pull/{number}","state":"OPEN","isDraft":true{extra or ""}}`
end

local function worktree(repository: string?, branch: string?): types.Worktree
	return {
		path = path.parse(`/src/{branch or "detached"}`),
		branch = branch,
		repository = repository,
		primary = false,
	}
end

local function hasArgument(argv: { string }, value: string): boolean
	return table.find(argv, value) ~= nil
end

local function isAuthoredQuery(argv: { string }): boolean
	return argv[5]:find("viewer", 1, true) ~= nil
end

test.case("GitHub looks up pull requests by each worktree branch", function(assert)
	local branchQuery: { string } = {}
	local pullRequests = github.listPullRequests({ worktree("example/widgets", "feature/hop") }, function(argv)
		if isAuthoredQuery(argv) then
			return result(true, '{"data":{"viewer":{"pullRequests":{"nodes":[]}}}}', "")
		end
		branchQuery = argv
		return result(
			true,
			`\{"data":\{"branch1":\{"defaultBranchRef":\{"name":"main"},"pullRequests":\{"nodes":[{pullRequestJson(
				42,
				"feature/hop"
			)}]}}}}`,
			""
		)
	end)
	assert.eq(branchQuery[1], "gh")
	assert.eq(branchQuery[3], "graphql")
	assert.eq(hasArgument(branchQuery, "owner1=example"), true)
	assert.eq(hasArgument(branchQuery, "name1=widgets"), true)
	assert.eq(hasArgument(branchQuery, "branch1=feature/hop"), true)
	assert.eq(#pullRequests, 1)
	assert.eq(pullRequests[1].number, 42)
	assert.eq(pullRequests[1].state, "OPEN")
	assert.eq(pullRequests[1].draft, true)
	assert.eq(pullRequests[1].repository, "example/widgets")
end)

test.case("GitHub skips default branches and fork pull requests", function(assert)
	local pullRequests = github.listPullRequests({
		worktree("example/widgets", "main"),
		worktree("example/widgets", "feature/hop"),
	}, function(argv)
		if isAuthoredQuery(argv) then
			return result(true, '{"data":{"viewer":{"pullRequests":{"nodes":[]}}}}', "")
		end
		return result(
			true,
			`\{"data":\{"branch1":\{"defaultBranchRef":\{"name":"main"},"pullRequests":\{"nodes":[{pullRequestJson(
				1,
				"main"
			)}]}},`
				.. `"branch2":\{"defaultBranchRef":\{"name":"main"},"pullRequests":\{"nodes":[{pullRequestJson(
					2,
					"feature/hop",
					',"isCrossRepository":true'
				)}]}}}}`,
			""
		)
	end)
	assert.eq(#pullRequests, 0)
end)

test.case("GitHub includes the viewer's open pull requests only for known repositories", function(assert)
	local pages = 0
	local pullRequests = github.listPullRequests({ worktree("example/widgets", nil) }, function(argv)
		pages += 1
		if pages == 1 then
			return result(
				true,
				`\{"data":\{"viewer":\{"pullRequests":\{"pageInfo":\{"hasNextPage":true,"endCursor":"next"},"nodes":[`
					.. `{pullRequestJson(7, "idea", ',"repository":{"nameWithOwner":"example/widgets"}')},`
					.. `{pullRequestJson(8, "other", ',"repository":{"nameWithOwner":"example/unknown"}')}]}}}}`,
				""
			)
		end
		assert.eq(hasArgument(argv, "cursor=next"), true)
		return result(
			true,
			`\{"data":\{"viewer":\{"pullRequests":\{"pageInfo":\{"hasNextPage":false},"nodes":[{pullRequestJson(
				9,
				"later",
				',"repository":{"nameWithOwner":"example/widgets"}'
			)}]}}}}`,
			""
		)
	end)
	assert.eq(pages, 2)
	assert.eq(#pullRequests, 2)
	assert.eq(pullRequests[1].number, 7)
	assert.eq(pullRequests[2].number, 9)
end)

test.case("GitHub matches the viewer's pull requests to remotes regardless of case", function(assert)
	local pullRequests = github.listPullRequests({ worktree("example/widgets", nil) }, function()
		return result(
			true,
			`\{"data":\{"viewer":\{"pullRequests":\{"nodes":[{pullRequestJson(
				7,
				"idea",
				',"repository":{"nameWithOwner":"Example/Widgets"}'
			)}]}}}}`,
			""
		)
	end)
	assert.eq(#pullRequests, 1)
	assert.eq(pullRequests[1].repository, "example/widgets")
end)

test.case("GitHub batches branch lookups into shared requests", function(assert)
	local worktrees: { types.Worktree } = {}
	for index = 1, 60 do
		table.insert(worktrees, worktree("example/widgets", `branch-{index}`))
	end
	local branchCalls = 0
	github.listPullRequests(worktrees, function(argv)
		if not isAuthoredQuery(argv) then
			branchCalls += 1
		end
		return result(true, '{"data":{}}', "")
	end)
	assert.eq(branchCalls, 3)
end)

test.case("GitHub keeps branches that resolved when others in the batch fail", function(assert)
	local pullRequests = github.listPullRequests({
		worktree("example/widgets", "feature/hop"),
		worktree("example/missing", "feature/hop"),
	}, function(argv)
		if isAuthoredQuery(argv) then
			return result(false, "", "rate limited")
		end
		return result(
			false,
			`\{"data":\{"branch1":\{"pullRequests":\{"nodes":[{pullRequestJson(42, "feature/hop")}]}},"branch2":null},"errors":[]}`,
			"Could not resolve to a Repository"
		)
	end)
	assert.eq(#pullRequests, 1)
	assert.eq(pullRequests[1].repository, "example/widgets")
end)

test.case("GitHub skips gh entirely without GitHub repositories", function(assert)
	local calls = 0
	local pullRequests = github.listPullRequests({ worktree(nil, "main") }, function()
		calls += 1
		return result(false, "", "not authenticated")
	end)
	assert.eq(calls, 0)
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
