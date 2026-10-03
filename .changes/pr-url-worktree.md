---
bump: minor
category: Features
---

`hop <PR URL>` checks out a pull request that has no local worktree and opens it. The new worktree sits beside the repository's primary checkout as `<folder>-pr-<number>` and tracks the PR's branch; fork PRs are fetched into a `pr-<number>` branch. Pasting a PR URL into **Hop: Go** shows that PR's worktree, or offers to check it out. Selecting a pull request without a worktree in **Hop: Go** now opens or checks out its worktree instead of the browser; its row button still opens the PR.
