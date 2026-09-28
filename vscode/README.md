# Hop for VS Code

Hop switches one VS Code window between your worktrees. Run **Hop: Go** to search every worktree Hop knows about by repository, branch, PR number (`flipbook#482`), or PR title, then switch to it in the same window. Each word narrows the results, and `default` matches a repository's default-branch checkout, so `flipbook default` finds it without naming the branch. A repository's default-branch checkout is listed first, then the most recently used worktrees.

Each switch opens the checkout as the window's only workspace folder. VS Code reloads the window and its extensions when the folder changes.

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
