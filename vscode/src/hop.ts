import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import * as path from "node:path";

// Mirrors `hop list --json`. Hop owns discovery and PR association; this is only its shape.
export interface HopPullRequest {
	repository: string;
	number: number;
	title?: string;
	url: string;
	branch: string;
	state?: string;
	draft?: boolean;
	author?: string;
}

export interface HopWorktree {
	repository: { name: string; root?: string; remote?: string };
	path: string;
	branch?: string;
	head?: string;
	primary: boolean;
	onDefaultBranch?: boolean;
	// Seconds since the epoch that the worktree was last used.
	lastActivity?: number;
	pr?: HopPullRequest;
}

export interface HopList {
	generatedAt: number;
	worktrees: HopWorktree[];
	pullRequests: HopPullRequest[];
	// Worktrees Hop checked out for other people's PRs, reached only by PR reference.
	others?: HopWorktree[];
}

export function allWorktrees(list: HopList): HopWorktree[] {
	return [...list.worktrees, ...(list.others ?? [])];
}

export function resolveHopPath(extensionPath: string, configured: string): string {
	if (configured !== "") {
		return configured;
	}
	const bundled = path.join(extensionPath, "bin", "hop");
	return existsSync(bundled) ? bundled : "hop";
}

function run(hop: string, args: string[]): Promise<string> {
	return new Promise((resolve, reject) => {
		execFile(hop, args, { maxBuffer: 64 * 1024 * 1024 }, (error, stdout) => {
			if (error) {
				// hop reports its own errors on stdout.
				const message = stdout.trim() || error.message;
				reject(new Error(`hop ${args.join(" ")} failed: ${message}`));
				return;
			}
			resolve(stdout);
		});
	});
}

export async function list(hop: string, refresh: boolean): Promise<HopList> {
	const stdout = await run(hop, ["list", "--json", ...(refresh ? ["--refresh"] : [])]);
	try {
		return JSON.parse(stdout) as HopList;
	} catch {
		throw new Error("hop returned invalid JSON");
	}
}

// Opens the worktree for `expression`, checking out a PR first when needed. Hop hands the folder
// back to this extension through its URI handler.
export async function to(hop: string, expression: string): Promise<void> {
	await run(hop, ["to", expression]);
}
