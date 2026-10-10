import 'package:ai_bank_receipt_manager/application/reconciliation/financial_change_detector.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';

/// WinForms entry tracking and mandatory financial reconciliation rules.
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

  /// Preview financial diffs without writing. Empty when no recon is required.
  Future<List<FinancialFieldDiff>> previewFinancialEdit({
    required String id,
    required ReceiptFinancialPatch patch,
  }) async {
    final existing = await _receipts.getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.entryStatus != DbEntryStatus.entered) {
      return const [];
    }
    return FinancialChangeDetector.detect(existing, patch);
  }

  /// Applies an edit. Financial changes on Entered receipts require
  /// [userConfirmedReconciliation] = true. Cancelled edits must not call this.
  Future<ReceiptRecord> applyFinancialEdit({
    required String id,
    required String changedBy,
    double? newAmount,
    String? newPartyName,
    String? newMappedAccountId,
    String? newCustomerId,
    String? newDealerId,
    String? newAdminMessage,
    String? newNotes,
    String? newTransactionId,
    DateTime? newAccountingDate,
    DbReceiptType? newReceiptType,
    bool clearTransactionId = false,
    bool clearCustomerId = false,
    bool clearDealerId = false,
    bool clearMappedAccountId = false,
    bool userConfirmedReconciliation = false,
    String? correctionNotes,
  }) {
    return applyPatch(
      id: id,
      changedBy: changedBy,
      patch: ReceiptFinancialPatch(
        amount: newAmount,
        accountingDate: newAccountingDate,
        receiptType: newReceiptType,
        mappedAccountId: newMappedAccountId,
        customerId: newCustomerId,
        dealerId: newDealerId,
        transactionId: newTransactionId,
        adminMessage: newAdminMessage,
        notes: newNotes,
        partyDisplayName: newPartyName,
        clearTransactionId: clearTransactionId,
        clearCustomerId: clearCustomerId,
        clearDealerId: clearDealerId,
        clearMappedAccountId: clearMappedAccountId,
      ),
      userConfirmedReconciliation: userConfirmedReconciliation,
      correctionNotes: correctionNotes,
    );
  }

  Future<ReceiptRecord> applyPatch({
    required String id,
    required ReceiptFinancialPatch patch,
    required String changedBy,
    bool userConfirmedReconciliation = false,
    String? correctionNotes,
  }) async {
    final existing = await _receipts.getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }

    final diffs = FinancialChangeDetector.detect(existing, patch);
    final wasEntered = existing.entryStatus == DbEntryStatus.entered;
    final raiseReconciliation = wasEntered && diffs.isNotEmpty;

    if (raiseReconciliation && !userConfirmedReconciliation) {
      throw StateError(
        'Financial edit after Entered requires explicit reconciliation '
        'confirmation. The office entry may need a manual correction.',
      );
    }

    final proposed = FinancialChangeDetector.applyPatch(existing, patch);
    final enteredAt = existing.enteredAt;

    if (!raiseReconciliation) {
      return _receipts.updateReceipt(
        updated: proposed.copyWith(
          entryStatus: existing.entryStatus,
          enteredAt: enteredAt,
          enteredBy: existing.enteredBy,
          reviewStatus: existing.reviewStatus,
          priorAmount: existing.priorAmount,
          priorPartyName: existing.priorPartyName,
          priorAccountId: existing.priorAccountId,
          reconciliationCompletedAt: existing.reconciliationCompletedAt,
        ),
        changedBy: changedBy,
        reason: diffs.isEmpty
            ? 'Non-financial receipt fields updated.'
            : 'Receipt fields updated before Entered.',
      );
    }

    final caseRecord = ReconciliationCaseRecord(
      id: '', // repository assigns
      receiptId: existing.id,
      status: ReconciliationCaseStatus.open,
      kind: ReconciliationCaseKind.financialEdit,
      reason:
          'Financial values changed after Entered. The office entry may '
          'require manual correction.',
      correctionNotes: correctionNotes,
      diffs: diffs,
      previousAmount: existing.amount,
      correctedAmount: proposed.amount,
      openedAt: DateTime.now().toUtc(),
      openedBy: changedBy,
      createdAt: DateTime.now().toUtc(),
    );

    return _receipts.applyEnteredFinancialCorrection(
      updated: proposed.copyWith(
        // Never silently reset Entered tick or entered timestamp.
        entryStatus: DbEntryStatus.entered,
        enteredAt: enteredAt,
        enteredBy: existing.enteredBy,
        winformsReference: existing.winformsReference,
        priorAmount: existing.amount,
        priorPartyName:
            patch.partyDisplayName ??
            existing.priorPartyName ??
            existing.adminMessage,
        priorAccountId: existing.mappedAccountId,
        reviewStatus: DbReviewStatus.needsReconciliation,
        clearReconciliationCompletedAt: true,
      ),
      caseRecord: caseRecord,
      changedBy: changedBy,
      reason:
          'Financial edit after Entered — reconciliation required; tick kept.',
    );
  }

  /// Marks WinForms correction completed. Status returns to Entered.
  Future<ReceiptRecord> confirmReconciliationReviewed({
    required String id,
    required String reviewedBy,
    String? correctionNotes,
  }) {
    return _receipts.completeReconciliation(
      id: id,
      completedBy: reviewedBy,
      correctionNotes: correctionNotes,
    );
  }

  Future<ReceiptRecord> reopenReconciliation({
    required String id,
    required String reopenedBy,
    String? reason,
  }) {
    return _receipts.reopenReconciliation(
      id: id,
      reopenedBy: reopenedBy,
      reason: reason,
    );
  }

  Future<ReconciliationCaseRecord> addCorrectionNotes({
    required String caseId,
    required String notes,
    required String changedBy,
  }) {
    return _receipts.addReconciliationCorrectionNotes(
      caseId: caseId,
      notes: notes,
      changedBy: changedBy,
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
    return _receipts.updateReceipt(
      updated: existing.copyWith(
        reviewStatus: DbReviewStatus.needsReconciliation,
      ),
      changedBy: changedBy,
      reason:
          'Delete requested for Entered receipt — reconcile office entry first.',
    );
  }

  /// Soft-deletes an Entered receipt and opens a deletion reconciliation case.
  Future<ReceiptRecord> softDeleteAfterReview({
    required String id,
    required String changedBy,
  }) {
    return _receipts.softDeleteEnteredWithReconciliationCase(
      id: id,
      changedBy: changedBy,
    );
  }

  Future<List<ReconciliationCaseRecord>> listCasesForReceipt(String receiptId) {
    return _receipts.listReconciliationCases(receiptId);
  }

  Future<List<ReconciliationCaseRecord>> listOpenCases({
    DateTime? accountingDate,
  }) {
    return _receipts.listOpenReconciliationCases(
      accountingDate: accountingDate,
    );
  }
}
