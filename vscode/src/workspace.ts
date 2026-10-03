import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";

// Recognize the old shell so an existing window can migrate to a single-folder checkout.
const SHELL_FILE = path.join(os.homedir(), ".hop", "shell.code-workspace");

export interface Target {
	path: string;
}

export function isShell(): boolean {
	return vscode.workspace.workspaceFile?.fsPath === SHELL_FILE;
}

// Only a single-folder window or the old shell has one worktree in use. Other multi-root workspaces
// have none, so Hop neither labels them with a worktree nor treats one as the current checkout.
export function activePath(): string | undefined {
	const folders = vscode.workspace.workspaceFolders ?? [];
	if (isShell()) {
		return folders[1]?.uri.fsPath;
	}
	return vscode.workspace.workspaceFile === undefined && folders.length === 1 ? folders[0].uri.fsPath : undefined;
}

export async function switchTo(target: Target): Promise<void> {
	// The old shell reopens even on the same worktree to migrate to a single-folder window.
	if (!isShell() && activePath() === target.path) {
		return;
	}

	await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(target.path), {
		forceReuseWindow: true,
	});
}
