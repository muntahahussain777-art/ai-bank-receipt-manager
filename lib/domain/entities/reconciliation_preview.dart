import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';

class ReconciliationPreview {
  const ReconciliationPreview({
    required this.reference,
    required this.oldAmount,
    required this.newAmount,
    required this.oldParty,
    required this.newParty,
    required this.oldOfficeAccount,
    required this.newOfficeAccount,
    this.fieldDiffs = const [],
    this.winFormsMessage =
        'The office entry may need a manual correction. This app never changes '
        'the office system. Confirm only after you understand the difference.',
  });

  final String reference;
  final double oldAmount;
  final double newAmount;
  final String oldParty;
  final String newParty;
  final OfficeAccount oldOfficeAccount;
  final OfficeAccount newOfficeAccount;
  final List<FinancialFieldDiff> fieldDiffs;

  /// User-facing safety note about correcting the office entry.
  final String winFormsMessage;
}
