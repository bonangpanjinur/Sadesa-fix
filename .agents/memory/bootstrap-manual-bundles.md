---
name: Bootstrap manual bundles
description: Recent POS hardening bundles are canonical additions in supabase/bootstrap and are not part of the archived migration source set.
---

The bootstrap manifest can contain ordered manual POS hardening bundles that do not exist in `archive/supabase/migrations`; validate the manifest without passing the archive source directory unless those migrations are first added to the archive.

**Why:** The archive validator compares against the historical source set, while the repository's current bootstrap sequence includes later operational hardening bundles maintained directly in `supabase/bootstrap`.

**How to apply:** Add a new ordered bootstrap SQL file and manifest entry together, then run the default bootstrap validator. Treat archive-source validation failures for the existing manual tail as a baseline limitation, not as evidence that the manifest entry is missing.