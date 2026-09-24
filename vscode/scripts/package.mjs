// Builds the hop CLI, bundles it into bin/, and packages a macOS arm64 VSIX.
import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const extension = dirname(dirname(fileURLToPath(import.meta.url)));
const repository = dirname(extension);
const run = (command, args, cwd) => execFileSync(command, args, { cwd, stdio: "inherit" });

run("lute", ["run", "build"], repository);
mkdirSync(join(extension, "bin"), { recursive: true });
copyFileSync(join(repository, "build", "hop"), join(extension, "bin", "hop"));
chmodSync(join(extension, "bin", "hop"), 0o755);

run("npx", ["tsc", "-p", "."], extension);
run("npx", ["vsce", "package", "--target", "darwin-arm64", "--no-dependencies", "--out", "hop.vsix"], extension);
