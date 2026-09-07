---
name: POS receipt print contract
description: Durable boundary between POS receipt printing and marketplace invoice documents.
---

POS checkout receipts and POS reprints should use one persisted, idempotent print contract with an explicit printed-versus-queued result and a controlled browser fallback. Marketplace invoices are documents with A4/browser-print behavior, not thermal POS receipts.

**Why:** Treating every print surface as the same document creates duplicate-print risk and makes device-specific failures invisible to cashiers.

**How to apply:** Route new POS receipt and reprint flows through the shared receipt contract; keep invoice layout/printing separate unless the product explicitly introduces invoice-to-thermal conversion.