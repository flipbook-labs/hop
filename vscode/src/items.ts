import type { HopList, HopPullRequest, HopWorktree } from "./hop";

// Plain Quick Pick item data, kept free of the vscode module so it can be unit tested.
export type Target =
	| { kind: "worktree"; worktree: HopWorktree }
	| { kind: "pullRequest"; pullRequest: HopPullRequest }
	| { kind: "checkout"; repository: string; number: number };

// A pasted PR URL, `owner/repo#123`, `repo#123`, or `#123`. Bare numbers stay ordinary search words.
export interface PullRequestReference {
	number: number;
	repository?: string;
	repositoryName?: string;
}

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
	switch (target.kind) {
		case "worktree":
			return target.worktree.path;
		case "pullRequest":
			return target.pullRequest.url;
		case "checkout":
			return `${target.repository}#${target.number}`;
	}
}

const REPOSITORY = String.raw`[\w.-]+/[\w.-]+`;
const NAME = String.raw`[\w.-]+`;

export function parsePullRequestReference(query: string): PullRequestReference | undefined {
	const text = query.trim();
	const full =
		text.match(new RegExp(String.raw`^https?://github\.com/(${REPOSITORY})/pull/(\d+)`, "i")) ??
		text.match(new RegExp(String.raw`^(${REPOSITORY})#(\d+)$`));
	if (full) {
		return { repository: full[1], number: Number(full[2]) };
	}
	const named = text.match(new RegExp(String.raw`^(${NAME})#(\d+)$`));
	if (named) {
		return { repositoryName: named[1], number: Number(named[2]) };
	}
	const bare = text.match(/^#(\d+)$/);
	return bare ? { number: Number(bare[1]) } : undefined;
}

function repositoryMatches(reference: PullRequestReference, repository: string): boolean {
	const normalized = repository.toLowerCase();
	if (reference.repository) {
		return normalized === reference.repository.toLowerCase();
	}
	if (reference.repositoryName) {
		return repositoryName(normalized) === reference.repositoryName.toLowerCase();
	}
	return true;
}

function referenceMatches(reference: PullRequestReference, pullRequest: HopPullRequest | undefined): boolean {
	return (
		pullRequest !== undefined &&
		pullRequest.number === reference.number &&
		repositoryMatches(reference, pullRequest.repository)
	);
}

// Mirrors `hop to`: a full reference names its repository; otherwise the PR must be the only known
// match, or the repository name must match exactly one known repository.
function checkoutTarget(
	list: HopList,
	reference: PullRequestReference,
	pullRequests: HopPullRequest[],
): Target | undefined {
	if (reference.repository) {
		return { kind: "checkout", repository: reference.repository, number: reference.number };
	}
	if (pullRequests.length === 1) {
		return { kind: "checkout", repository: pullRequests[0].repository, number: reference.number };
	}
	if (pullRequests.length > 1 || !reference.repositoryName) {
		return undefined;
	}
	const repositories = new Map<string, string>();
	for (const worktree of list.worktrees) {
		const remote = worktree.repository.remote;
		if (remote && repositoryMatches(reference, remote)) {
			repositories.set(remote.toLowerCase(), remote);
		}
	}
	const [repository, ...others] = repositories.values();
	return repository && others.length === 0 ? { kind: "checkout", repository, number: reference.number } : undefined;
}

export function checkoutItem(target: Target & { kind: "checkout" }): Item {
	return {
		label: `$(git-pull-request-create) Check out ${target.repository}#${target.number}`,
		detail: "Create a local worktree for this pull request",
		target,
	};
}

function pullRequestReferenceItems(
	list: HopList,
	reference: PullRequestReference,
	home: string,
	currentPath: string | undefined,
): Item[] {
	const worktrees = list.worktrees.filter((worktree) => referenceMatches(reference, worktree.pr));
	if (worktrees.length > 0) {
		return worktrees.map((worktree) => worktreeItem(worktree, home, worktree.path === currentPath));
	}
	const pullRequests = list.pullRequests.filter((pullRequest) => referenceMatches(reference, pullRequest));
	const items: Item[] = [];
	const target = checkoutTarget(list, reference, pullRequests);
	if (target?.kind === "checkout") {
		items.push(checkoutItem(target));
	}
	if (pullRequests.length > 0) {
		items.push({ label: "Pull requests without a worktree", separator: true });
		items.push(...pullRequests.map(pullRequestItem));
	}
	return items;
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

// A query word that matches worktrees on their repository's default branch.
const DEFAULT_KEYWORD = "default";

function words(query: string): string[] {
	return query.toLowerCase().split(/\s+/).filter((word) => word !== "");
}

function pullRequestFields(pullRequest: HopPullRequest): string[] {
	return [pullRequest.title ?? "", `${repositoryName(pullRequest.repository)}#${pullRequest.number}`];
}

function worktreeFields(worktree: HopWorktree): string[] {
	return [
		worktree.branch ?? "",
		worktree.path.split("/").pop() ?? "",
		worktree.repository.name,
		worktree.repository.remote ?? "",
		...(worktree.pr ? pullRequestFields(worktree.pr) : []),
	];
}

function everyWordMatches(fields: string[], queryWords: string[], isDefault = false): boolean {
	const lowered = fields.map((field) => field.toLowerCase());
	return queryWords.every(
		(word) => (word === DEFAULT_KEYWORD && isDefault) || lowered.some((field) => field.includes(word)),
	);
}

// A query naming a repository puts that repository's default-branch checkout first.
function namesDefaultCheckout(worktree: HopWorktree, queryWords: string[]): boolean {
	if (!worktree.onDefaultBranch) {
		return false;
	}
	const names = [worktree.repository.name.toLowerCase(), worktree.repository.remote?.toLowerCase()];
	return queryWords.some((word) => names.includes(word));
}

// A PR reference lists the worktree for that PR, or offers to check it out.
// Without a query: recently picked worktrees first, then everything else by repository.
// With a query: every word must match a branch, folder, repository, or PR; a named repository's
// default-branch checkout comes first, then the most recently changed. The current worktree goes last.
export function buildItems(
	list: HopList,
	recent: string[],
	currentPath: string | undefined,
	home: string,
	query = "",
): Item[] {
	const reference = parsePullRequestReference(query);
	if (reference) {
		return pullRequestReferenceItems(list, reference, home, currentPath);
	}
	const queryWords = words(query);
	const rank = new Map(recent.map((value, index) => [value, index]));
	const worktrees = list.worktrees
		.filter((worktree) => everyWordMatches(worktreeFields(worktree), queryWords, worktree.onDefaultBranch))
		.sort((left, right) => {
			const leftCurrent = left.path === currentPath;
			const rightCurrent = right.path === currentPath;
			if (leftCurrent !== rightCurrent) {
				return leftCurrent ? 1 : -1;
			}
			if (queryWords.length > 0) {
				const pinned = Number(namesDefaultCheckout(right, queryWords)) - Number(namesDefaultCheckout(left, queryWords));
				const activity = (right.lastActivity ?? 0) - (left.lastActivity ?? 0);
				return pinned || activity || compareWorktrees(left, right);
			}
			const leftRank = rank.get(left.path) ?? Infinity;
			const rightRank = rank.get(right.path) ?? Infinity;
			if (leftRank !== rightRank) {
				return leftRank - rightRank;
			}
			return compareWorktrees(left, right);
		});
	const pullRequests = list.pullRequests.filter((pullRequest) =>
		everyWordMatches(pullRequestFields(pullRequest), queryWords),
	);

	const items = worktrees.map((worktree) => worktreeItem(worktree, home, worktree.path === currentPath));
	if (pullRequests.length > 0) {
		items.push({ label: "Pull requests without a worktree", separator: true });
		items.push(...pullRequests.map(pullRequestItem));
	}
	return items;
}

export function recordRecent(recent: string[], worktreePath: string, limit = 20): string[] {
	return [worktreePath, ...recent.filter((value) => value !== worktreePath)].slice(0, limit);
}
