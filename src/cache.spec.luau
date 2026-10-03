local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local test = require("@std/test")

local cache = require("@root/cache")
local snapshot = require("@root/core/snapshot")

local function temporaryHome(name: string): path.Path
	local directory = path.join(system.tmpdir(), `hop-cache-{process.pid()}-{name}`)
	if fs.exists(directory) then
		fs.removeDirectory(directory, { recursive = true })
	end
	fs.createDirectory(directory, { makeParents = true })
	return directory
end

test.case("cache round-trips a snapshot", function(assert)
	local home = temporaryHome("roundtrip")
	local store = cache.new(home)
	assert.eq(store.read(), nil)
	store.write(snapshot.build({
		{
			path = path.parse("/src/widgets-feature"),
			branch = "feature/hop",
			repository = "example/widgets",
			root = "/src/widgets",
			head = "abc123",
			defaultBranch = "main",
			primary = false,
		},
	}, {
		{
			number = 42,
			url = "https://github.com/example/widgets/pull/42",
			branch = "feature/hop",
			repository = "example/widgets",
			title = "Add hop",
			state = "OPEN",
			draft = false,
		},
	}, 1234))

	local value = store.read() or error("expected cached snapshot")
	assert.eq(value.generatedAt, 1234)
	local entry = value.entries[1]
	assert.eq(tostring(entry.worktree.path), "/src/widgets-feature")
	assert.eq(entry.worktree.head, "abc123")
	assert.eq(entry.worktree.root, "/src/widgets")
	assert.eq(entry.worktree.defaultBranch, "main")
	local pullRequest = entry.pullRequest or error("expected PR")
	assert.eq(pullRequest.title, "Add hop")
	assert.eq(pullRequest.draft, false)
end)

test.case("cache treats malformed files as absent", function(assert)
	local home = temporaryHome("malformed")
	local file = cache.cachePath(home)
	fs.createDirectory(path.dirname(file), { makeParents = true })
	fs.writeStringToFile(file, "{not json")
	assert.eq(cache.new(home).read(), nil)
	fs.writeStringToFile(file, '{"worktrees": []}')
	assert.eq(cache.new(home).read(), nil)
end)
