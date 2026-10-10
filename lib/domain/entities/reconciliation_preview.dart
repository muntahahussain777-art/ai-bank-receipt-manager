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
  });

  final String reference;
  final double oldAmount;
  final double newAmount;
  final String oldParty;
  final String newParty;
  final OfficeAccount oldOfficeAccount;
  final OfficeAccount newOfficeAccount;
}
