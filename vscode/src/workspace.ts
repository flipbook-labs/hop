import { mkdirSync, writeFileSync } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";

// Hop keeps one window as a persistent shell: a workspace whose first folder is a fixed,
// empty anchor and whose second folder is the active worktree. VS Code restarts every
// extension when the first folder changes, so only the second folder is ever swapped.
const HOP_DIRECTORY = path.join(os.homedir(), ".hop");
const ANCHOR = path.join(HOP_DIRECTORY, "shell");
const SHELL_FILE = path.join(HOP_DIRECTORY, "shell.code-workspace");

export interface Target {
	path: string;
	name: string;
}

export function isShell(): boolean {
	return vscode.workspace.workspaceFile?.fsPath === SHELL_FILE;
}

export function activePath(): string | undefined {
	const folders = vscode.workspace.workspaceFolders ?? [];
	return (isShell() ? folders[1] : folders[0])?.uri.fsPath;
}

function waitForFolderChange(): Promise<void> {
	return new Promise((resolve) => {
		const subscription = vscode.workspace.onDidChangeWorkspaceFolders(() => {
			subscription.dispose();
			resolve();
		});
	});
}

export async function switchTo(target: Target): Promise<void> {
	if (activePath() === target.path) {
		return;
	}
	const folder = { uri: vscode.Uri.file(target.path), name: target.name };

	if (isShell()) {
		const existing = (vscode.workspace.workspaceFolders ?? []).length;
		const changed = waitForFolderChange();
		if (!vscode.workspace.updateWorkspaceFolders(1, Math.max(existing - 1, 0), folder)) {
			throw new Error(`VS Code refused to open ${target.path}`);
		}
		await changed;
		return;
	}

	// Entering the shell from any other window reloads it once, in place.
	mkdirSync(ANCHOR, { recursive: true });
	const contents = {
		folders: [
			{ path: ANCHOR, name: "hop" },
			{ path: target.path, name: target.name },
		],
	};
	writeFileSync(SHELL_FILE, `${JSON.stringify(contents, null, "\t")}\n`);
	await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(SHELL_FILE), {
		forceReuseWindow: true,
	});
}
