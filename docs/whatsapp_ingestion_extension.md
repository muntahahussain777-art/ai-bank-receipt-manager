# WhatsApp / receipt ingestion extension

## What this app supports today

1. **Android Share Intent** — share an image or PDF from WhatsApp (or any app) into AI Bank Receipt Manager.
2. **Manual gallery / camera / multi-select / PDF picker** — user-driven import.
3. **Manual receipt entry** — type fields without an image.
4. **Durable batch queue** — files are copied to local storage before AI runs; failures keep the original file.

These paths all produce `IngestedFile` values that enter the same batch → review → `appendImport` pipeline.

## What is intentionally not implemented

Ordinary personal WhatsApp groups **cannot** be read automatically through an official unrestricted API.

This project does **not**:

- scrape WhatsApp Web or the WhatsApp app
- use Accessibility Service automation to read chats
- claim unofficial “WhatsApp sync” access

## Extension interface

Implement `ReceiptIngestionSource` in `lib/application/import/receipt_ingestion.dart`:

- `sourceId` / `displayName`
- `isAvailable`
- `getInitialFiles()`
- `watchIncomingFiles()`

Register the source beside `AndroidShareIngestionSource` in providers. Downstream batch processing must not need changes.

## Future authorized automation

If Meta / WhatsApp later offers an **official, supported** business integration that the office is authorized to use, add a new `ReceiptIngestionSource` implementation that emits `IngestedFile` (or cached media paths) into the existing queue.

Do not alter receipt financial rules, Groq extraction, or WinForms boundaries when adding that source.
