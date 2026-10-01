---
bump: minor
category: Features
---

Other people's pull requests now have their own space. A PR reference that isn't yours is checked out under `~/.hop/cache`, cloning the repository there when you don't have it, so pasting any GitHub PR URL works. These worktrees stay out of your list and searches; a PR reference reopens them without contacting GitHub. A reference that names its repository no longer triggers a full refresh when the cache misses. Bare numbers such as `123` are now search words that match `repo#123`, the same as in **Hop: Go**; use `#123` for a PR reference.
