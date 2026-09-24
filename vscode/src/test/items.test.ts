import * as assert from "node:assert/strict";
import { test } from "node:test";

import type { HopList } from "../hop";
import { buildItems, recordRecent } from "../items";

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

test("recordRecent moves a path to the front and caps the list", () => {
	assert.deepEqual(recordRecent(["a", "b", "c"], "b"), ["b", "a", "c"]);
	assert.deepEqual(recordRecent(["a", "b"], "c", 2), ["c", "a"]);
});
