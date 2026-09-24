import * as vscode from "vscode";

import * as hop from "./hop";
import { recordRecent } from "./items";
import { pick } from "./picker";
import * as workspace from "./workspace";

const RECENT_KEY = "hop.recent";

export function activate(context: vscode.ExtensionContext): void {
	let latest: hop.HopList | undefined;
	let refreshing: Promise<hop.HopList> | undefined;

	const hopPath = () =>
		hop.resolveHopPath(context.extensionPath, vscode.workspace.getConfiguration("hop").get("path", ""));
	const remember = (list: hop.HopList) => {
		latest = list;
		updateStatus();
		return list;
	};
	const cached = () => hop.list(hopPath(), false).then(remember);
	const refresh = () => {
		refreshing ??= hop
			.list(hopPath(), true)
			.then(remember)
			.finally(() => {
				refreshing = undefined;
			});
		return refreshing;
	};
	const recent = () => context.globalState.get<string[]>(RECENT_KEY, []);

	const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
	status.command = "hop.go";
	status.tooltip = "Hop: Go";
	context.subscriptions.push(status);

	function updateStatus(): void {
		const current = workspace.activePath();
		if (!workspace.isShell() || current === undefined) {
			status.hide();
			return;
		}
		const worktree = latest?.worktrees.find((candidate) => candidate.path === current);
		const name = worktree
			? `${worktree.repository.name} · ${worktree.branch ?? "detached"}`
			: (vscode.workspace.workspaceFolders?.[1]?.name ?? current);
		const pullRequest = worktree?.pr ? ` · #${worktree.pr.number}` : "";
		status.text = `$(git-branch) ${name}${pullRequest}`;
		status.show();
	}

	async function go(worktree: hop.HopWorktree): Promise<void> {
		await context.globalState.update(RECENT_KEY, recordRecent(recent(), worktree.path));
		await workspace.switchTo({
			path: worktree.path,
			name: `${worktree.repository.name} · ${worktree.branch ?? "detached"}`,
		});
		updateStatus();
	}

	const report = (error: unknown) =>
		void vscode.window.showErrorMessage(error instanceof Error ? error.message : String(error));

	context.subscriptions.push(
		vscode.commands.registerCommand("hop.go", async () => {
			const target = await pick({ cached, refresh, recent, currentPath: workspace.activePath });
			if (target?.kind === "worktree") {
				await go(target.worktree).catch(report);
			}
		}),
		vscode.commands.registerCommand("hop.refresh", () =>
			vscode.window.withProgress(
				{ location: vscode.ProgressLocation.Window, title: "Hop: refreshing worktrees" },
				() => refresh().then(() => undefined, report)
			)
		),
		// `hop <expr>` in a terminal hands off here: vscode://flipbook-labs.hop/to?path=<worktree>
		vscode.window.registerUriHandler({
			handleUri: async (uri) => {
				if (uri.path !== "/to") {
					return;
				}
				const requested = new URLSearchParams(uri.query).get("path");
				try {
					// Only mount folders Hop already knows about, never arbitrary paths from a link.
					const find = (list: hop.HopList) => list.worktrees.find((worktree) => worktree.path === requested);
					const worktree = find(await cached()) ?? find(await refresh());
					if (!worktree) {
						throw new Error(`Hop does not know a worktree at ${requested}`);
					}
					await go(worktree);
				} catch (error) {
					report(error);
				}
			},
		}),
		vscode.workspace.onDidChangeWorkspaceFolders(updateStatus)
	);

	if (workspace.isShell()) {
		updateStatus();
		cached().catch(() => undefined);
	}
}

export function deactivate(): void {}
