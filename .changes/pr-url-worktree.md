---
bump: minor
category: Features
---

`hop <PR URL>` checks out a pull request that has no local worktree and opens it. The new worktree sits beside the repository's primary checkout as `<folder>-pr-<number>` and tracks the PR's branch; fork PRs are fetched into a `pr-<number>` branch. Pasting a PR URL into **Hop: Go** shows that PR's worktree, or offers to check it out.
