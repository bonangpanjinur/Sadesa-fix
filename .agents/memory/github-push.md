---
name: GitHub push path
description: GitHub remote HTTPS authentication is unavailable in this workspace; use the attached GitHub connector for pushes.
---

Use the connected GitHub integration to publish commits when the local HTTPS remote rejects authentication.

**Why:** The repository remote is reachable, but direct Git push cannot authenticate with the workspace's available credentials.

**How to apply:** Verify the target repository and branch through the GitHub API, then create/update the Git tree, commit, and branch ref through the connected GitHub integration.