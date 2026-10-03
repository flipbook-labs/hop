// Builds the hop CLI, bundles it into bin/, and packages a macOS VSIX for the host architecture,
// since the bundled CLI is a native build for the machine that ran this script.
import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const extension = dirname(dirname(fileURLToPath(import.meta.url)));
const repository = dirname(extension);
const run = (command, args, cwd) => execFileSync(command, args, { cwd, stdio: "inherit" });

if (process.platform !== "darwin") {
	throw new Error("Hop only supports macOS, so the extension can only be packaged on a Mac.");
}

run("lute", ["run", "build"], repository);
mkdirSync(join(extension, "bin"), { recursive: true });
copyFileSync(join(repository, "build", "hop"), join(extension, "bin", "hop"));
chmodSync(join(extension, "bin", "hop"), 0o755);

run("npx", ["tsc", "-p", "."], extension);
const target = `darwin-${process.arch}`;
run("npx", ["vsce", "package", "--target", target, "--no-dependencies", "--out", "hop.vsix"], extension);
