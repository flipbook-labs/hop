---
bump: patch
category: Fixes
---

`hop list --refresh` no longer caches results when GitHub fails to return a repository's pull requests, so the next command retries instead of showing missing PRs. Repositories GitHub reports as not found, such as deleted ones, are still cached.
