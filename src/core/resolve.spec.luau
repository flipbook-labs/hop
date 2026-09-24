local test = require("@std/test")

local resolve = require("@root/core/resolve")

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
