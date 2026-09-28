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

export function activePath(): string | undefined {
	const folders = vscode.workspace.workspaceFolders ?? [];
	return (isShell() ? folders[1] : folders[0])?.uri.fsPath;
}

export async function switchTo(target: Target): Promise<void> {
	const folders = vscode.workspace.workspaceFolders ?? [];
	if (vscode.workspace.workspaceFile === undefined && folders.length === 1 && folders[0].uri.fsPath === target.path) {
		return;
	}

	await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(target.path), {
		forceReuseWindow: true,
	});
}
