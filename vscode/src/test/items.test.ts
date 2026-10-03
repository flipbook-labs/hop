import * as assert from "node:assert/strict";
import { test } from "node:test";

import type { HopList } from "../hop";
import { buildItems, parsePullRequestReference, recordRecent } from "../items";

const list: HopList = {
	generatedAt: 0,
	worktrees: [
		{
			repository: { name: "flipbook", remote: "flipbook-labs/flipbook" },
			path: "/home/me/git/flipbook",
			branch: "main",
			primary: true,
		},
		{
			repository: { name: "flipbook", remote: "flipbook-labs/flipbook" },
			path: "/home/me/git/flipbook-story-api",
			branch: "feat/new-story-api",
			primary: false,
			pr: {
				repository: "flipbook-labs/flipbook",
				number: 482,
				title: "Add new story API",
				url: "https://github.com/flipbook-labs/flipbook/pull/482",
				branch: "feat/new-story-api",
				state: "OPEN",
				draft: false,
			},
		},
		{
			repository: { name: "hop", remote: "flipbook-labs/hop" },
			path: "/home/me/git/hop",
			branch: "main",
			primary: true,
		},
	],
	pullRequests: [
		{
			repository: "flipbook-labs/flipbook",
			number: 491,
			title: "Fix story loading race",
			url: "https://github.com/flipbook-labs/flipbook/pull/491",
			branch: "agent/fix-story-loading",
			state: "OPEN",
			draft: true,
		},
	],
};

test("worktree items carry repository, branch, searchable PR reference, and short path", () => {
	const items = buildItems(list, [], undefined, "/home/me");
	const feature = items.find((item) => item.label.includes("feat/new-story-api"));
	assert.ok(feature);
	assert.equal(feature.label, "$(git-branch) feat/new-story-api");
	assert.equal(feature.description, "flipbook");
	assert.equal(feature.detail, "flipbook#482 · Add new story API · open · ~/git/flipbook-story-api");
	assert.equal(items[0].detail, "no PR · ~/git/flipbook");
});

test("pull requests without a worktree follow a separator", () => {
	const items = buildItems(list, [], undefined, "/home/me");
	const separatorIndex = items.findIndex((item) => item.separator);
	assert.equal(separatorIndex, 3);
	const orphan = items[separatorIndex + 1];
	assert.equal(orphan.label, "$(git-pull-request) #491 Fix story loading race");
	assert.equal(orphan.detail, "flipbook#491 · Fix story loading race · draft · no local worktree");
	assert.equal(orphan.target?.kind, "pullRequest");
});

test("recent worktrees come first and the current worktree goes last", () => {
	const items = buildItems(list, ["/home/me/git/hop"], "/home/me/git/flipbook", "/home/me");
	const worktreePaths = items.flatMap((item) => (item.target?.kind === "worktree" ? [item.target.worktree.path] : []));
	assert.deepEqual(worktreePaths, [
		"/home/me/git/hop",
		"/home/me/git/flipbook-story-api",
		"/home/me/git/flipbook",
	]);
	assert.equal(items[2].description, "flipbook · current");
});

const searchList: HopList = {
	generatedAt: 0,
	worktrees: [
		{
			repository: { name: "uiblox", remote: "org/uiblox" },
			path: "/src/uiblox",
			branch: "master",
			primary: true,
			onDefaultBranch: true,
			lastActivity: 10,
		},
		{
			repository: { name: "uiblox", remote: "org/uiblox" },
			path: "/src/uiblox-migration",
			branch: "UIBLOX-1-font-migration",
			primary: false,
			onDefaultBranch: false,
			lastActivity: 20,
		},
		{
			repository: { name: "uiblox", remote: "org/uiblox" },
			path: "/src/uiblox-tokens",
			branch: "UIBLOX-2-tokens",
			primary: false,
			onDefaultBranch: false,
			lastActivity: 30,
		},
		{
			repository: { name: "apps", remote: "org/apps" },
			path: "/src/apps-uiblox-update",
			branch: "UIBLOX-3-update",
			primary: false,
			onDefaultBranch: false,
			lastActivity: 40,
		},
		{
			repository: { name: "apps", remote: "org/apps" },
			path: "/src/apps",
			branch: "main",
			primary: true,
			onDefaultBranch: true,
			lastActivity: 50,
		},
	],
	pullRequests: [],
};

function searchPaths(query: string, currentPath?: string): string[] {
	return buildItems(searchList, [], currentPath, "/home/me", query).flatMap((item) =>
		item.target?.kind === "worktree" ? [item.target.worktree.path] : [],
	);
}

test("a repository query lists its default-branch checkout first, then the most recently used", () => {
	assert.deepEqual(searchPaths("uiblox"), [
		"/src/uiblox",
		"/src/apps-uiblox-update",
		"/src/uiblox-tokens",
		"/src/uiblox-migration",
	]);
});

test("every query word must match", () => {
	assert.deepEqual(searchPaths("uiblox m"), ["/src/uiblox", "/src/uiblox-migration"]);
	assert.deepEqual(searchPaths("uiblox missing"), []);
});

test("default matches default-branch checkouts without naming the branch", () => {
	assert.deepEqual(searchPaths("uiblox default"), ["/src/uiblox"]);
	assert.deepEqual(searchPaths("default"), ["/src/apps", "/src/uiblox"]);
});

test("the current worktree still goes last when searching", () => {
	assert.deepEqual(searchPaths("uiblox", "/src/uiblox"), [
		"/src/apps-uiblox-update",
		"/src/uiblox-tokens",
		"/src/uiblox-migration",
		"/src/uiblox",
	]);
});

test("searching matches PR references and titles, and filters orphaned PRs", () => {
	assert.deepEqual(
		buildItems(list, [], undefined, "/home/me", "flipbook#482").map((item) => item.target?.kind),
		["worktree"],
	);
	const items = buildItems(list, [], undefined, "/home/me", "loading race");
	assert.equal(items.length, 2);
	assert.ok(items[0].separator);
	assert.equal(items[1].target?.kind, "pullRequest");
});

test("parsePullRequestReference accepts URLs and #-references but not bare numbers", () => {
	assert.deepEqual(parsePullRequestReference(" https://github.com/Roblox/foundation/pull/2186/files "), {
		repository: "Roblox/foundation",
		number: 2186,
	});
	assert.deepEqual(parsePullRequestReference("Roblox/foundation#2186"), {
		repository: "Roblox/foundation",
		number: 2186,
	});
	assert.deepEqual(parsePullRequestReference("foundation#2186"), { repositoryName: "foundation", number: 2186 });
	assert.deepEqual(parsePullRequestReference("#2186"), { number: 2186 });
	assert.equal(parsePullRequestReference("2186"), undefined);
	assert.equal(parsePullRequestReference("foundation fonts"), undefined);
});

function kinds(query: string): (string | undefined)[] {
	return buildItems(list, [], undefined, "/home/me", query).map((item) => item.target?.kind);
}

test("a pasted PR URL lists its worktree", () => {
	const items = buildItems(list, [], undefined, "/home/me", "https://github.com/flipbook-labs/flipbook/pull/482");
	assert.equal(items.length, 1);
	const target = items[0].target;
	assert.equal(target?.kind === "worktree" && target.worktree.path, "/home/me/git/flipbook-story-api");
});

test("a pasted PR URL without a worktree offers to check it out", () => {
	const items = buildItems(list, [], undefined, "/home/me", "https://github.com/Roblox/foundation/pull/2186");
	assert.equal(items.length, 1);
	assert.equal(items[0].label, "$(git-pull-request-create) Check out Roblox/foundation#2186");
	assert.deepEqual(items[0].target, { kind: "checkout", repository: "Roblox/foundation", number: 2186 });
});

test("a pasted fork PR URL lists its pr-<number> worktree", () => {
	const forks: HopList = {
		...list,
		worktrees: [
			...list.worktrees,
			{
				repository: { name: "flipbook", remote: "flipbook-labs/flipbook" },
				path: "/home/me/git/flipbook-pr-558",
				branch: "pr-558",
				primary: false,
			},
		],
	};
	const items = buildItems(forks, [], undefined, "/home/me", "https://github.com/flipbook-labs/flipbook/pull/558");
	assert.equal(items.length, 1);
	const target = items[0].target;
	assert.equal(target?.kind === "worktree" && target.worktree.path, "/home/me/git/flipbook-pr-558");
});

test("short PR references offer a checkout only when they name one repository", () => {
	assert.deepEqual(kinds("#491"), [undefined, "pullRequest"]);
	assert.deepEqual(kinds("hop#7"), ["checkout"]);
	assert.deepEqual(kinds("#7"), []);
	assert.deepEqual(kinds("missing#7"), []);
});

test("only paths inside the home directory are shortened", () => {
	const sibling: HopList = {
		generatedAt: 0,
		worktrees: [
			{ repository: { name: "home" }, path: "/home/me", branch: "main", primary: true },
			{ repository: { name: "other" }, path: "/home/me2/project", branch: "main", primary: true },
		],
		pullRequests: [],
	};
	const details = buildItems(sibling, [], undefined, "/home/me/").map((item) => item.detail);
	assert.deepEqual(details, ["no PR · ~", "no PR · /home/me2/project"]);
});

test("recordRecent moves a path to the front and caps the list", () => {
	assert.deepEqual(recordRecent(["a", "b", "c"], "b"), ["b", "a", "c"]);
	assert.deepEqual(recordRecent(["a", "b"], "c", 2), ["c", "a"]);
});
