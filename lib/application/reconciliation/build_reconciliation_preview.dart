import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/entities/reconciliation_preview.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';

ReconciliationPreview buildReconciliationPreview({
  required Receipt receipt,
  required double newAmount,
  required String newParty,
  required OfficeAccount newOfficeAccount,
  List<FinancialFieldDiff> fieldDiffs = const [],
}) {
  return ReconciliationPreview(
    reference: receipt.reference,
    oldAmount: receipt.baselineAmount,
    newAmount: newAmount,
    oldParty: receipt.baselinePartyName,
    newParty: newParty,
    oldOfficeAccount: receipt.baselineOfficeAccount,
    newOfficeAccount: newOfficeAccount,
    fieldDiffs: fieldDiffs,
  );
}

ReconciliationPreview buildPreviewFromDiffs({
  required Receipt receipt,
  required List<FinancialFieldDiff> diffs,
  required double newAmount,
  required String newParty,
  required OfficeAccount newOfficeAccount,
}) {
  return buildReconciliationPreview(
    receipt: receipt,
    newAmount: newAmount,
    newParty: newParty,
    newOfficeAccount: newOfficeAccount,
    fieldDiffs: diffs,
  );
}
