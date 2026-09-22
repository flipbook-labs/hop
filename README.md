# Hop

Hop joins local Cursor and Claude Code sessions to Git worktrees. It can list recent work, open the matching folder in VS Code, resume a Cursor session, or jump from a GitHub pull request to an existing worktree.

## Install

Hop requires macOS, Git, the GitHub CLI, SQLite, VS Code's `code` launcher, and Cursor's `agent` launcher for the commands that use them.

```sh
rokit install
lute run install
lute setup
lute run build
```

The native executable is written to `build/hop`. To install a released version through Rokit:

```sh
rokit add --global flipbook-labs/hop
```

## Commands

```text
hop recent [--limit N] [--repo OWNER/REPO] [--agent cursor|claude] [--json]
hop go [NUMBER|QUERY]
hop pr <URL|NUMBER>
hop cursor [NUMBER|QUERY]
hop help
```

`hop recent` merges active top-level Cursor sessions with Claude Code JSONL sessions and sorts them by last activity. Cursor metadata is queried from its SQLite database in read-only mode. If either provider is unavailable, Hop continues with the other provider.

`hop go` opens a folder with `code <folder>`. `hop pr` resolves a GitHub PR with `gh` and reports an error when its branch has no local worktree. `hop cursor` runs `agent --workspace <folder> --resume <composer-id>`.

Ambiguous results use a numbered terminal picker.

## Configuration

Hop searches from the home directory by default. To narrow discovery, create `~/.hop/config.luau`:

```luau
return {
	roots = {
		"/path/to/source",
	},
}
```

Hop discovers primary Git repositories at most four directories below each root and asks each primary for its complete linked-worktree list. It does not follow symlinks, scans at most 200 primaries, and skips common large home-directory folders and dependency caches.

## Development

```sh
rokit install
lute run install
lute setup
lute run analyze
lute test
lute run build
```

Tests are colocated as `*.spec.luau`. Runtime subprocesses are routed through an injected command runner so adapters and CLI behavior can be tested without invoking local tools.
