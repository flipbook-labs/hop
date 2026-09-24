---
bump: minor
category: Features
---

`hop <expr>` and **Hop: Go** can open a repository's default-branch checkout. Searching `flipbook default` finds it without naming the branch, and searching `flipbook` lists it first. Each word of a search now narrows the results, so `flipbook m` finds `master`, and remaining matches are ordered by most recent use. `hop list --json` reports `onDefaultBranch` and `lastActivity` for each worktree.
