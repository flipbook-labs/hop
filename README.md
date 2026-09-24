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
hop <expr>
hop to <expr>
hop list [--refresh] [--no-pr] [--json]
hop recent [--limit N] [--repo OWNER/REPO] [--agent cursor|claude] [--json]
hop cursor [NUMBER|QUERY]
hop help
```

`hop <expr>` is shorthand for `hop to <expr>`, which opens the matching worktree with `code <folder>`. An expression is a pull request (`owner/repo#123`, `repo#123`, `#123`, `123`, or a PR URL) or a query that matches branches, repositories, folder names, and PR titles. Ambiguous results use a numbered terminal picker. A PR without a local worktree is reported with its URL.

`hop list` shows every discovered worktree with its associated pull request, plus open pull requests that have no local worktree. Results are cached in `~/.hop/cache/worktrees.json`. `--refresh` rediscovers worktrees and queries GitHub with one `gh pr list` per repository. `hop to` refreshes the cache once when nothing matches. `--no-pr` skips GitHub and does not update the cache. `--json` prints the same data for tools such as editor integrations.

`hop recent` merges active top-level Cursor sessions with Claude Code JSONL sessions and sorts them by last activity. Cursor metadata is queried from its SQLite database in read-only mode. If either provider is unavailable, Hop continues with the other provider.

`hop cursor` runs `agent --workspace <folder> --resume <composer-id>`.

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
