---
name: Replit runtime config
description: The environment-specific workflow for changing validated Replit runtime configuration.
---

Replit runtime configuration files such as `.replit` may reject direct edits. Write the candidate configuration to a workspace temporary file and use the platform's schema-validated replacement flow.

**Why:** Direct patching of `.replit` was rejected even though the requested module change was valid; validation prevents malformed workflow/runtime configuration from landing.

**How to apply:** Use the validated replacement callback for `.replit` changes, then restart the affected workflow and verify its logs.