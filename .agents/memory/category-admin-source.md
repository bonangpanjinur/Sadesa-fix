---
name: Admin category source
description: The public category menu is driven by active admin-managed category rows.
---

The frontend category menu must read active categories from the admin-managed categories table; do not recreate a second hard-coded menu list.

**Why:** Admin needs one place to rename, reorder, activate, or deactivate categories without the frontend drifting out of sync.

**How to apply:** When adding category UI, consume the shared category query/mapper and preserve the database slug for product compatibility.