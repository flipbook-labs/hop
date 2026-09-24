# Hop for VS Code

Hop turns one VS Code window into a persistent shell for your worktrees. Run **Hop: Go** to search every worktree Hop knows about by repository, branch, PR number (`flipbook#482`), or PR title, then switch to it in the same window. Each word narrows the results, and `default` matches a repository's default-branch checkout, so `flipbook default` finds it without naming the branch. A repository's default-branch checkout is listed first, then the most recently used worktrees.

The first switch reloads the window once into a Hop workspace (`~/.hop/shell.code-workspace`). Its first folder is an empty `hop` anchor and its second folder is the active worktree. Later switches only replace the second folder, so VS Code does not restart extensions or open another window.

`hop <expr>` in a terminal hands off to the extension through `vscode://flipbook-labs.hop/to?path=…` and switches the most recently focused window.

Pull requests without a local worktree appear at the end of the list and open in the browser. Worktree rows with a PR have a button to open it.

## Install

```sh
npm ci
npm run package
code --install-extension hop.vsix
```

`npm run package` builds the `hop` CLI with Lute and bundles it into the extension. Set `hop.path` to use a different executable.

The extension has no runtime dependencies, sends no telemetry, and makes no network requests. GitHub data comes from `hop`, which uses your `gh` login.
