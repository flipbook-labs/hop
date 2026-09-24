local fs = require("@std/fs")
local project = require("@repo/project")
local system = require("@std/system")
local run = require("./common/run")

local outputPath = tostring(project.BUILD_OUTPUT)
local windowsOutputPath = outputPath .. ".exe"

for _, stalePath in { outputPath, windowsOutputPath } do
	if fs.exists(stalePath) then
		fs.remove(stalePath)
	end
end

if system.os:lower() == "windows_nt" then
	outputPath = windowsOutputPath
end

if not fs.exists(project.BUILD_PATH) then
	fs.createDirectory(project.BUILD_PATH, { makeParents = true })
end

run({
	"lute",
	"compile",
	"cli.luau",
	"--output",
	outputPath,
	"--bundle-stats",
	"--show-require-graph",
})
assert(fs.exists(outputPath) and fs.type(outputPath) == "file", `native build did not produce {outputPath}`)
