local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")

local packagesDir = path.resolve("packages")
local storeDir = path.join(process.homedir(), ".loom", "store")

if not fs.exists(packagesDir) then
	fs.createDirectory(packagesDir, { makeParents = true })
end

local installed = process.run({ "lute", "pkg", "install" }, { stdio = "inherit" })
assert(installed.ok, `lute pkg install failed ({installed.exitcode})`)

local lock = require("@repo/loom.lock")

fs.removeDirectory(packagesDir, { recursive = true })
fs.createDirectory(packagesDir)

for packageId in lock.packages :: { [string]: unknown } do
	local copied = process.run({
		"cp",
		"-R",
		tostring(path.join(storeDir, packageId)),
		tostring(path.join(packagesDir, packageId)),
	})
	assert(copied.ok, `failed to vendor {packageId}: {copied.stderr}`)
end
