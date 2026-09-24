local path = require("@std/path")

export type CommandResult = {
	ok: boolean,
	exitCode: number,
	stdout: string,
	stderr: string,
}

export type CommandRunner = ({ string }) -> CommandResult

export type Worktree = {
	path: path.Path,
	branch: string?,
	repository: string?,
	root: string?,
	head: string?,
	defaultBranch: string?,
	primary: boolean,
}

export type PullRequest = {
	number: number,
	url: string,
	branch: string,
	repository: string,
	title: string?,
	state: string?,
	draft: boolean?,
}

export type Message = {
	role: string,
	text: string,
	timestamp: string?,
}

export type Session = {
	agent: "cursor" | "claude",
	id: string,
	title: string?,
	directory: string?,
	branchAtSessionTime: string?,
	updatedAt: number,
	needsAttention: boolean?,
	filesChanged: number?,
	messages: () -> () -> Message?,
}

export type Provider = {
	name: "cursor" | "claude",
	sessions: (self: Provider) -> { Session },
}

return {}
