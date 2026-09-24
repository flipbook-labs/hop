local run = require("./common/run")

run({ "stylua", "--check", "." })
run({ "lute", "lint", "src", "cli.luau", ".lute", "project.luau", "loom.config.luau" })
run({ "lute", "check", "src", "cli.luau", ".lute", "project.luau", "loom.config.luau" })
