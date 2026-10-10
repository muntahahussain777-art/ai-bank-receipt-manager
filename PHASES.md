# Implementation phases

Phase 1 is the only phase implemented. Do not start a later phase until it is requested.

The office rules in this file stay in force for every phase.

## Business requirements

1. WhatsApp screenshots may contain a bank receipt and a message written by the admin.
2. Groq Vision will eventually read the transaction details from those screenshots.
3. Mutalib is Azlan Traders.
4. AD is Habib Enterprise.
5. Customers send money to Mutalib or AD.
6. Mutalib and AD send money to dealers.
7. The WhatsApp admin note identifies the office customer or dealer.
8. Bank transaction direction and office accounting attribution are different. A credit or debit describes the bank account. The customer or dealer comes from the admin note.
9. The app prepares daily lists so a person can type them into the existing C# WinForms application.
10. The app must never directly modify WinForms or its database.

## Mandatory capabilities

These are required before the product is complete. Phase 1 only reserves a place for them in the interface.

- Persistent receipt records
- Historical accounting dates
- Append new receipts without overwriting existing records
- Permanent Pending, Entered, and Needs Reconciliation statuses
- Duplicate detection
- Financial edit reconciliation warnings
- Multiple Groq API configurations
- Secure key management
- Manual and batch WhatsApp receipt imports
- PDF and XLSX reports
- Full database and image backup
- Safe restore
- Offline support
- Audit history
- Data-loss prevention

## Hard boundaries

- Never open, write, or migrate the WinForms database from this app.
- Never describe a preview, a button press, or a closed dialog as a saved accounting entry.
- Bank direction and office attribution stay separate fields.
- Restore must not delete current data until a backup of that current data exists, and a failed restore must leave current data in place.
- API keys must not be written into a plain-text backup.

## Phase 1 — Application shell

Status: implemented.

- Flutter Android project, Material 3, Riverpod, go_router
- Light and dark themes
- Screens: Dashboard, Import Receipts, Daily Entries, Receipt Details, Calendar / History, Pending Entries, Entered Entries, Reconciliation Required, Customers, Dealers, Account Mapping, Groq AI Settings, Reports, Backup and Restore, General Settings
- Preview data for 10 October 2026 and a few earlier accounting dates
- Receipt card and reconciliation dialog
- Architecture folders: `core`, `domain`, `application`, `data`, `presentation`, `shared`

Intentionally not wired:

- Persistence, image import, Groq, export, backup, restore, audit log
- Status changes are not saved
- Confirm on the reconciliation dialog does not write a record

## Phase 2 — Local receipt records

Status: data layer implemented. UI still uses Phase 1 preview providers and has not been wired to SQLite yet.

Implemented under `lib/data/`:

- SQLite schema and additive migrations for Receipt, AccountMapping, Customer, Dealer, AppSettings, GroqApiConfiguration, ReceiptAuditHistory, ImportBatch
- Append-only imports, permanent entry status, historical accounting dates, soft delete / restore / confirmed permanent delete
- Duplicate detection without automatic deletion
- Audit history for amount, party, dates, notes, and entry status
- Database + receipt-image backup and confirmed restore with a safety copy
- Persistence tests in `test/persistence_repository_test.dart`

Still remaining for a later UI wiring step:

- Bind screens and Riverpod providers to the repositories
- Store Needs Reconciliation as the durable review/entry workflow in the UI
- Reject a save that would drop existing rows at the application/UI boundary

## Phase 3 — Dynamic office accounts and classification

Status: implemented for office accounts, customers/dealers, alias matching, and classification rules. Daily entry screens still use preview receipt rows.

- Mutalib / AD are one-time editable SQLite seeds, not hardcoded permanent identities
- Unlimited office accounts with aliases, activate/deactivate, archive/restore, safe delete
- Customer and dealer CRUD with aliases and usual office account links
- Business classification: customer→office incoming, office→dealer outgoing for any active account
- Ambiguous aliases and admin/bank conflicts mark Needs Review without auto-merge
- Dashboard office activity cards load dynamically from SQLite
- Tests in `test/phase3_office_accounts_test.dart`

Still remaining after Phase 3:

- Bind Daily / Pending / Entered / Reconciliation screens fully to stored receipts
- Persist classification choices onto receipt rows from the import UI
- Still do not connect to WinForms

## Phase 4 — Groq configuration

- Store more than one Groq configuration.
- Keep API keys in platform secure storage.
- Do not place keys in the database export or a plain backup.
- A failed or missing key must not erase receipt records.

## Phase 5 — WhatsApp image import

- Manual import of one screenshot.
- Batch import of many screenshots.
- Keep the image with the receipt record.
- A screenshot may contain both the bank receipt and the admin message.
- Import appends. It does not replace the existing day.

## Phase 6 — Extraction and duplicates

- Send a stored image to Groq Vision and show the extracted fields for review.
- The person confirms customer or dealer attribution from the admin note before the receipt joins the daily list.
- Detect duplicate receipts and keep both candidates visible until a person decides.
- Extraction failure must leave the image and any earlier record intact.

## Phase 7 — Financial edit reconciliation

- When amount, party, or office account changes after a receipt was prepared or marked entered, raise Needs Reconciliation.
- Show the old financial values, the new financial values, and that the correction is typed into WinForms by hand.
- Do not apply the change to WinForms.
- Keep the warning until a person records that the manual correction was reviewed.

## Phase 8 — Reports

- PDF daily entry list for the selected accounting date.
- XLSX daily entry list.
- PDF reconciliation worksheet.
- Reports read stored data. They do not change statuses or WinForms.

## Phase 9 — Backup and safe restore

- Back up the database and receipt images together.
- Restore only after a confirmed backup of the current data.
- If restore fails, keep the current data.
- Leave API keys in secure storage rather than in the backup file.
- Backup and restore must work offline.

## Phase 10 — Audit and data-loss prevention

- Record who changed a financial field, when, and the old and new values.
- Keep the audit history across backup and restore.
- Block silent overwrite, silent status changes, and deletes that are not explicit.
- Verify that an interrupted write does not leave a partial receipt as the only copy.

## Suggested order

Phase 2, then 3, then 4 and 5, then 6, then 7, then 8, then 9, then 10.

Duplicate detection can start once images and records both exist (Phase 6). Reconciliation warnings depend on stored financial history (Phase 7). Backup is last among the file features so it copies real records and images, not the Phase 1 preview.
