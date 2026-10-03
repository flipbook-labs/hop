# Changelog

All notable changes to Hop will be documented here.


## v0.1.0

### Features

- `hop <expr>` and **Hop: Go** can open a repository's default-branch checkout. Searching `flipbook default` finds it without naming the branch, and searching `flipbook` lists it first. Each word of a search now narrows the results, so `flipbook m` finds `master`, and remaining matches are ordered by most recent change. `hop list --json` reports `onDefaultBranch` and `lastActivity` for each worktree.

- Add `hop <expr>`/`hop to` for jumping to worktrees by PR reference, branch, repository, or PR title, and `hop list` for browsing cached worktrees with their pull requests. `hop go` and `hop pr` are replaced by `hop to`.

- Add the Hop CLI with local session, worktree, and pull-request navigation.

- Every command now accepts `--help`, and `hop help <command>` describes a single command. Error messages no longer include internal source locations.

- Other people's pull requests now have their own space. A PR reference that isn't yours is checked out under `~/.hop/cache`, cloning the repository there when you don't have it, so pasting any GitHub PR URL works. These worktrees stay out of your list and searches; a PR reference reopens them without contacting GitHub. Bare numbers such as `123` are now search words that match `repo#123`, the same as in **Hop: Go**; use `#123` for a PR reference.

- `hop <PR URL>` checks out a pull request that has no local worktree and opens it. The new worktree sits beside the repository's primary checkout as `<folder>-pr-<number>` and tracks the PR's branch; fork PRs are fetched into a `pr-<number>` branch. Pasting a PR URL into **Hop: Go** shows that PR's worktree, or offers to check it out. Selecting a pull request without a worktree in **Hop: Go** now opens or checks out its worktree instead of the browser; its row button still opens the PR.

- The VS Code extension opens each worktree as the window's only workspace folder. This lets tools that expect a single workspace root use the checkout directly. Switching worktrees reloads the window and extensions. Multi-root workspaces that aren't Hop's no longer show a Hop worktree in the status bar.

- Add the Hop VS Code extension. **Hop: Go** searches worktrees and pull requests and switches the current window to the selected worktree in place. `hop <expr>` hands off to the extension when it is installed.
