# AI Bank Receipt Manager

Android desk for a Pakistan office that prepares WhatsApp bank-receipt entries for manual typing into an existing C# WinForms accounting application.

Phase 1 is a preview shell. It does not store receipts, call Groq, export files, or change WinForms.

## Requirements

- Flutter stable (this project was created with Flutter 3.38.9 and Dart 3.10.8)
- Android SDK, if you want to run it on a device or emulator

## Setup

```bash
flutter pub get
flutter run
```

Other checks:

```bash
dart format .
flutter analyze
flutter test
```

## Phase 1 scope

Included:

- Material 3 light and dark themes
- Riverpod state for the selected accounting date, visible month, and theme mode
- go_router navigation across the office screens
- Preview receipts, customers, dealers, and Groq configuration slots
- Receipt cards and a reconciliation review dialog

Not included:

- A database
- Image import
- Groq Vision calls or stored API keys
- PDF or XLSX export
- Backup and restore files
- Any write to the WinForms application or its database

Buttons that would perform those actions explain that they are not available. They do not report success.

The theme switch and the accounting-date filter change what the preview screens show. Both reset when the app process ends.

## Office rules

- Mutalib is Azlan Traders.
- AD is Habib Enterprise.
- Customers send money to Mutalib or AD.
- Mutalib and AD send money to dealers.
- The WhatsApp admin note identifies the customer or dealer.
- Bank credit or debit is not the same thing as office attribution.

See [PHASES.md](PHASES.md) for the work that comes after this shell.

## Project layout

```text
lib/
  core/            theme and formatting
  domain/          entities, enums, office rules
  application/     summary, reconciliation preview, providers
  data/preview/    labeled sample data
  presentation/    router, shell, screens
  shared/widgets/  receipt card, metrics, dialogs
```
