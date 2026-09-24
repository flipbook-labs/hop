import type { HopList, HopPullRequest, HopWorktree } from "./hop";

// Plain Quick Pick item data, kept free of the vscode module so it can be unit tested.
export type Target =
	| { kind: "worktree"; worktree: HopWorktree }
	| { kind: "pullRequest"; pullRequest: HopPullRequest };

export interface Item {
	label: string;
	description?: string;
	detail?: string;
	separator?: boolean;
	target?: Target;
}

function tilde(value: string, home: string): string {
	return home !== "" && value.startsWith(home) ? `~${value.slice(home.length)}` : value;
}

function repositoryName(repository: string): string {
	return repository.split("/").pop() ?? repository;
}

function status(pullRequest: HopPullRequest): string {
	return pullRequest.draft ? "draft" : (pullRequest.state ?? "").toLowerCase();
}

// `repo#123` in the detail line lets the fuzzy matcher find PRs the way they are usually written.
function pullRequestSummary(pullRequest: HopPullRequest): string {
	const parts = [`${repositoryName(pullRequest.repository)}#${pullRequest.number}`];
	if (pullRequest.title) {
		parts.push(pullRequest.title);
	}
	const state = status(pullRequest);
	if (state !== "") {
		parts.push(state);
	}
	return parts.join(" · ");
}

export function worktreeKey(target: Target): string {
	return target.kind === "worktree" ? target.worktree.path : target.pullRequest.url;
}

export function worktreeItem(worktree: HopWorktree, home: string, current: boolean): Item {
	const icon = worktree.primary ? "$(repo)" : "$(git-branch)";
	const summary = worktree.pr ? pullRequestSummary(worktree.pr) : "no PR";
	return {
		label: `${icon} ${worktree.branch ?? "detached"}`,
		description: current ? `${worktree.repository.name} · current` : worktree.repository.name,
		detail: `${summary} · ${tilde(worktree.path, home)}`,
		target: { kind: "worktree", worktree },
	};
}

export function pullRequestItem(pullRequest: HopPullRequest): Item {
	return {
		label: `$(git-pull-request) #${pullRequest.number} ${pullRequest.title ?? pullRequest.branch}`,
		description: repositoryName(pullRequest.repository),
		detail: `${pullRequestSummary(pullRequest)} · no local worktree`,
		target: { kind: "pullRequest", pullRequest },
	};
}

function compareWorktrees(left: HopWorktree, right: HopWorktree): number {
	return (
		left.repository.name.localeCompare(right.repository.name) ||
		Number(right.primary) - Number(left.primary) ||
		(left.branch ?? "").localeCompare(right.branch ?? "")
	);
}

// Recently used worktrees first, then everything else by repository; the current one goes last.
export function buildItems(list: HopList, recent: string[], currentPath: string | undefined, home: string): Item[] {
	const rank = new Map(recent.map((value, index) => [value, index]));
	const worktrees = [...list.worktrees].sort((left, right) => {
		const leftCurrent = left.path === currentPath;
		const rightCurrent = right.path === currentPath;
		if (leftCurrent !== rightCurrent) {
			return leftCurrent ? 1 : -1;
		}
		const leftRank = rank.get(left.path) ?? Infinity;
		const rightRank = rank.get(right.path) ?? Infinity;
		if (leftRank !== rightRank) {
			return leftRank - rightRank;
		}
		return compareWorktrees(left, right);
	});

	const items = worktrees.map((worktree) => worktreeItem(worktree, home, worktree.path === currentPath));
	if (list.pullRequests.length > 0) {
		items.push({ label: "Pull requests without a worktree", separator: true });
		items.push(...list.pullRequests.map(pullRequestItem));
	}
	return items;
}

export function recordRecent(recent: string[], worktreePath: string, limit = 20): string[] {
	return [worktreePath, ...recent.filter((value) => value !== worktreePath)].slice(0, limit);
}
