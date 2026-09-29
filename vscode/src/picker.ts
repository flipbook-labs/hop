import * as os from "node:os";
import * as vscode from "vscode";

import type { HopList } from "./hop";
import { buildItems, type Item, type Target, worktreeKey } from "./items";

export interface PickerSource {
	cached: () => Promise<HopList>;
	refresh: () => Promise<HopList>;
	recent: () => string[];
	currentPath: () => string | undefined;
}

type PickItem = vscode.QuickPickItem & { target?: Target };

const OPEN_PULL_REQUEST: vscode.QuickInputButton = {
	iconPath: new vscode.ThemeIcon("link-external"),
	tooltip: "Open pull request",
};

const REFRESH: vscode.QuickInputButton = {
	iconPath: new vscode.ThemeIcon("refresh"),
	tooltip: "Refresh worktrees and pull requests",
};

// Cached results older than this are refreshed in the background while the picker is open.
const STALE_SECONDS = 60;

function pullRequestUrl(target: Target | undefined): string | undefined {
	if (target?.kind === "worktree") {
		return target.worktree.pr?.url;
	}
	return target?.kind === "pullRequest" ? target.pullRequest.url : undefined;
}

function toPickItem(item: Item): PickItem {
	if (item.separator) {
		return { label: item.label, kind: vscode.QuickPickItemKind.Separator };
	}
	const hasPullRequest = pullRequestUrl(item.target) !== undefined;
	return {
		label: item.label,
		description: item.description,
		detail: item.detail,
		target: item.target,
		buttons: hasPullRequest ? [OPEN_PULL_REQUEST] : undefined,
		// buildItems already filtered by the query; VS Code's fuzzy filter cannot match words across fields.
		alwaysShow: true,
	};
}

export function openPullRequest(url: string): void {
	void vscode.env.openExternal(vscode.Uri.parse(url));
}

// Resolves with the selected row's target, or undefined when the picker closes without one.
// Rows with a pull request open it in the browser from their button.
export function pick(source: PickerSource): Promise<Target | undefined> {
	const picker = vscode.window.createQuickPick<PickItem>();
	picker.placeholder =
		"Search worktrees by repository, branch, PR number, PR title, or PR URL; `default` for the default branch";
	picker.matchOnDescription = true;
	picker.matchOnDetail = true;
	// Keeps Hop's ordering while filtering. It is missing from the stable typings, but the
	// extension host honors it.
	(picker as vscode.QuickPick<PickItem> & { sortByLabel: boolean }).sortByLabel = false;
	picker.buttons = [REFRESH];
	picker.busy = true;

	let closed = false;
	let current: HopList | undefined;
	const show = (list: HopList, keepActive = true) => {
		if (closed) {
			return;
		}
		current = list;
		const activeKey =
			keepActive && picker.activeItems[0]?.target ? worktreeKey(picker.activeItems[0].target) : undefined;
		const items = buildItems(list, source.recent(), source.currentPath(), os.homedir(), picker.value).map(
			toPickItem,
		);
		picker.items = items;
		const active = activeKey ? items.find((item) => item.target && worktreeKey(item.target) === activeKey) : undefined;
		if (active) {
			picker.activeItems = [active];
		}
	};
	picker.onDidChangeValue(() => {
		if (current) {
			show(current, false);
		}
	});
	const fail = (error: unknown) => {
		if (!closed) {
			void vscode.window.showErrorMessage(error instanceof Error ? error.message : String(error));
		}
	};
	const refresh = () => {
		picker.busy = true;
		return source
			.refresh()
			.then(show, fail)
			.finally(() => {
				picker.busy = false;
			});
	};

	source.cached().then((list) => {
		show(list);
		if (Date.now() / 1000 - list.generatedAt > STALE_SECONDS) {
			return refresh();
		}
		picker.busy = false;
	}, fail);

	return new Promise((resolve) => {
		picker.onDidTriggerButton(() => void refresh());
		picker.onDidTriggerItemButton(({ item }) => {
			const url = pullRequestUrl(item.target);
			if (url) {
				openPullRequest(url);
			}
		});
		picker.onDidAccept(() => {
			resolve(picker.selectedItems[0]?.target);
			picker.hide();
		});
		picker.onDidHide(() => {
			closed = true;
			resolve(undefined);
			picker.dispose();
		});
		picker.show();
	});
}
