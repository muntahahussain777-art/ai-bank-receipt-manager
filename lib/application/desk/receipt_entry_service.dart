import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';

/// WinForms entry tracking rules for the daily desk.
class ReceiptEntryService {
  ReceiptEntryService(this._receipts);

  final ReceiptRepository _receipts;

  Future<ReceiptRecord> markEntered({
    required String id,
    required String enteredBy,
    String? winformsReference,
  }) {
    return _receipts.markEntered(
      id: id,
      enteredBy: enteredBy,
      winformsReference: winformsReference,
    );
  }

  Future<ReceiptRecord> undoEntered({
    required String id,
    required bool confirmed,
    required String changedBy,
  }) {
    return _receipts.undoEntered(
      id: id,
      confirmed: confirmed,
      changedBy: changedBy,
    );
  }

  Future<List<ReceiptRecord>> markEnteredBulk({
    required List<String> ids,
    required String enteredBy,
  }) {
    return _receipts.markEnteredBulk(ids: ids, enteredBy: enteredBy);
  }

  /// Financial edits on Entered receipts keep the tick and raise reconciliation.
  Future<ReceiptRecord> applyFinancialEdit({
    required String id,
    required double newAmount,
    String? newPartyName,
    String? newMappedAccountId,
    String? newCustomerId,
    String? newDealerId,
    String? newAdminMessage,
    String? newTransactionId,
    DateTime? newAccountingDate,
    required String changedBy,
  }) async {
    final existing = await _receipts.getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }

    final financialChanged =
        (existing.amount - newAmount).abs() >= 0.0001 ||
        (newMappedAccountId != null &&
            newMappedAccountId != existing.mappedAccountId) ||
        (newCustomerId != null && newCustomerId != existing.customerId) ||
        (newDealerId != null && newDealerId != existing.dealerId) ||
        (newTransactionId != null &&
            newTransactionId != existing.transactionId);

    final wasEntered = existing.entryStatus == DbEntryStatus.entered;
    final raiseReconciliation = wasEntered && financialChanged;

    return _receipts.updateReceipt(
      updated: existing.copyWith(
        amount: newAmount,
        mappedAccountId: newMappedAccountId ?? existing.mappedAccountId,
        customerId: newCustomerId ?? existing.customerId,
        dealerId: newDealerId ?? existing.dealerId,
        adminMessage: newAdminMessage ?? existing.adminMessage,
        transactionId: newTransactionId ?? existing.transactionId,
        accountingDate: newAccountingDate ?? existing.accountingDate,
        // Never silently reset Entered.
        entryStatus: existing.entryStatus,
        enteredAt: existing.enteredAt,
        enteredBy: existing.enteredBy,
        priorAmount: raiseReconciliation ? existing.amount : existing.priorAmount,
        priorPartyName: raiseReconciliation
            ? (newPartyName ?? existing.priorPartyName ?? existing.adminMessage)
            : existing.priorPartyName,
        priorAccountId: raiseReconciliation
            ? existing.mappedAccountId
            : existing.priorAccountId,
        reviewStatus: raiseReconciliation
            ? DbReviewStatus.needsReconciliation
            : existing.reviewStatus,
      ),
      changedBy: changedBy,
      reason: raiseReconciliation
          ? 'Financial edit after Entered — reconciliation required; tick kept.'
          : 'Receipt fields updated.',
    );
  }

  Future<ReceiptRecord> confirmReconciliationReviewed({
    required String id,
    required String reviewedBy,
  }) async {
    final existing = await _receipts.getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    return _receipts.updateReceipt(
      updated: existing.copyWith(
        reviewStatus: DbReviewStatus.approved,
      ),
      changedBy: reviewedBy,
      reason: 'Manual WinForms correction reviewed.',
    );
  }

  Future<ReceiptRecord> requestDeleteReviewForEntered({
    required String id,
    required String changedBy,
  }) async {
    final existing = await _receipts.getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.entryStatus != DbEntryStatus.entered) {
      return _receipts.softDelete(id: id, changedBy: changedBy);
    }
    // Mark for reconciliation first; caller deletes after review.
    return _receipts.updateReceipt(
      updated: existing.copyWith(
        reviewStatus: DbReviewStatus.needsReconciliation,
      ),
      changedBy: changedBy,
      reason:
          'Delete requested for Entered receipt — reconcile WinForms first.',
    );
  }

  Future<ReceiptRecord> softDeleteAfterReview({
    required String id,
    required String changedBy,
  }) {
    return _receipts.softDelete(
      id: id,
      changedBy: changedBy,
      allowEnteredWithoutReconciliation: true,
      reason: 'Deleted after reconciliation review.',
    );
  }
}
