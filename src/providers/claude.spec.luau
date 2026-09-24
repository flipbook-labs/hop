local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local test = require("@std/test")

local Claude = require("@root/providers/claude")

local function projectsFixture(lines: { json.Value }): path.Path
	local projects = path.join(system.tmpdir(), `hop-claude-{process.pid()}`, "projects")
	if fs.exists(projects) then
		fs.removeDirectory(projects, { recursive = true })
	end
	local project = path.join(projects, "encoded-project")
	fs.createDirectory(project, { makeParents = true })
	local serialized: { string } = {}
	for _, line in lines do
		table.insert(serialized, json.serialize(line))
	end
	fs.writeStringToFile(path.join(project, "session-1.jsonl"), table.concat(serialized, "\n") .. "\n")
	return projects
end

test.case("Claude normalizes title, workspace, branch, timestamp, and messages", function(assert)
	local projects = projectsFixture({
		{
			type = "user",
			timestamp = "2026-09-14T16:36:29.862Z",
			cwd = "/src/widgets",
			gitBranch = "feature/widgets",
			message = { role = "user", content = { { type = "text", text = "Build the widgets" } } },
		},
		{ type = "ai-title", aiTitle = "Widget implementation", sessionId = "session-1" },
	})
	local sessions = Claude.new({ projectsPath = projects }):sessions()
	assert.eq(#sessions, 1)
	assert.eq(sessions[1].id, "session-1")
	assert.eq(sessions[1].title, "Widget implementation")
	assert.eq(sessions[1].directory, "/src/widgets")
	assert.eq(sessions[1].branchAtSessionTime, "feature/widgets")
	assert.eq(sessions[1].updatedAt > 0, true)
	local iterator = sessions[1].messages()
	local message = iterator()
	assert.eq(message and message.role, "user")
	assert.eq(message and message.text, "Build the widgets")
end)

test.case("Claude falls back to the first user message when aiTitle is absent", function(assert)
	local projects = projectsFixture({
		{
			type = "user",
			message = { role = "user", content = "Investigate the navigation failure" },
		},
	})
	local sessions = Claude.new({ projectsPath = projects }):sessions()
	assert.eq(sessions[1].title, "Investigate the navigation failure")
end)

test.case("Claude degrades to no sessions when its archive is unavailable", function(assert)
	local missing = path.join(system.tmpdir(), `hop-claude-missing-{process.pid()}`)
	assert.eq(#Claude.new({ projectsPath = missing }):sessions(), 0)
end)
