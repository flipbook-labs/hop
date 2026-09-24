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
}

export function resolveHopPath(extensionPath: string, configured: string): string {
	if (configured !== "") {
		return configured;
	}
	const bundled = path.join(extensionPath, "bin", "hop");
	return existsSync(bundled) ? bundled : "hop";
}

export function list(hop: string, refresh: boolean): Promise<HopList> {
	const args = ["list", "--json", ...(refresh ? ["--refresh"] : [])];
	return new Promise((resolve, reject) => {
		execFile(hop, args, { maxBuffer: 64 * 1024 * 1024 }, (error, stdout) => {
			if (error) {
				// hop reports its own errors on stdout.
				const message = stdout.trim() || error.message;
				reject(new Error(`hop ${args.join(" ")} failed: ${message}`));
				return;
			}
			try {
				resolve(JSON.parse(stdout) as HopList);
			} catch {
				reject(new Error("hop returned invalid JSON"));
			}
		});
	});
}
