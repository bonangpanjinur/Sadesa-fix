---
name: Offline reconnect timing
description: Browser online events can arrive before React has committed the online state used by POS sync callbacks.
---

POS offline queue synchronization should be initiated from an effect that observes the committed online state, rather than only from the `online` event handler.

**Why:** The browser event can fire while a callback still captures `isOnline === false`, causing reconnect sync to be skipped until a later interval.

**How to apply:** Keep the event handler responsible for updating connectivity state; let the state-driven effect start the idempotent sync.