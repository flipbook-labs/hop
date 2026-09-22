local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local test = require("@std/test")

local git = require("@root/git")
local types = require("@root/types")

local function successful(stdout: string): types.CommandResult
	return { ok = true, exitCode = 0, stdout = stdout, stderr = "" }
end

local function fixture(): (path.Path, path.Path, path.Path)
	local root = path.join(system.tmpdir(), `hop-git-{process.pid()}`)
	if fs.exists(root) then
		fs.removeDirectory(root, { recursive = true })
	end
	local primary = path.join(root, "src", "org", "repo")
	local linked = path.join(system.tmpdir(), `hop-linked-{process.pid()}`)
	fs.createDirectory(path.join(primary, ".git"), { makeParents = true })
	fs.createDirectory(linked, { makeParents = true })
	fs.writeStringToFile(path.join(linked, ".git"), "gitdir: elsewhere")
	fs.createDirectory(path.join(root, "Library", "hidden", ".git"), { makeParents = true })
	fs.createDirectory(path.join(root, "a", "b", "c", "d", "e", ".git"), { makeParents = true })
	return root, primary, linked
end

test.case("discovery skips excluded and over-depth repositories but includes linked worktrees", function(assert)
	local root, primary, linked = fixture()
	local calls = 0
	local worktrees = git.discover({ root }, {
		runner = function(argv)
			calls += 1
			if argv[6] == "origin" then
				return successful("git@github.com:example/widgets.git\n")
			end
			return successful(
				`worktree {primary}\nHEAD abc\nbranch refs/heads/main\n\nworktree {linked}\nHEAD def\nbranch refs/heads/feature/hop\n`
			)
		end,
	})
	assert.eq(calls, 2)
	assert.eq(#worktrees, 2)
	local first = worktrees[1]
	local second = worktrees[2]
	local linkedWorktree = if tostring(first.path) == tostring(linked) then first else second
	local primaryWorktree = if linkedWorktree == first then second else first
	assert.eq(tostring(linkedWorktree.path), tostring(linked))
	assert.eq(linkedWorktree.branch, "feature/hop")
	assert.eq(linkedWorktree.repository, "example/widgets")
	assert.eq(primaryWorktree.primary, true)
end)

test.case("discovery caps primary repositories", function(assert)
	local root = path.join(system.tmpdir(), `hop-git-limit-{process.pid()}`)
	if fs.exists(root) then
		fs.removeDirectory(root, { recursive = true })
	end
	fs.createDirectory(path.join(root, "a", ".git"), { makeParents = true })
	fs.createDirectory(path.join(root, "b", ".git"), { makeParents = true })
	local worktrees = git.discover({ root }, {
		maxPrimaries = 1,
		runner = function(argv)
			if argv[6] == "origin" then
				return successful("https://github.com/example/limited.git")
			end
			return successful(`worktree {path.join(root, "a")}\nbranch refs/heads/main\n`)
		end,
	})
	assert.eq(#worktrees, 1)
end)

test.case("remote parsing supports common GitHub URL forms", function(assert)
	assert.eq(git.repositoryFromRemote("git@github.com:org/repo.git"), "org/repo")
	assert.eq(git.repositoryFromRemote("https://github.com/org/repo"), "org/repo")
	assert.eq(git.repositoryFromRemote("https://example.com/org/repo"), nil)
end)
