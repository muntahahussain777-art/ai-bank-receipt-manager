import 'package:ai_bank_receipt_manager/application/desk/receipt_entry_service.dart';
import 'package:ai_bank_receipt_manager/application/reconciliation/financial_change_detector.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late ReceiptRepository receipts;
  late ReceiptEntryService entry;

  setUp(() async {
    harness = await TestDbHarness.create();
    receipts = harness.receipts;
    entry = ReceiptEntryService(receipts);
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<ReceiptRecord> seedEntered({
    double amount = 700000,
    String prefix = 'R7',
    String? customerId,
    String? dealerId,
    String? mappedAccountId,
  }) async {
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'phase7',
      drafts: [
        harness.draft(
          transactionId: '${prefix}_${DateTime.now().microsecondsSinceEpoch}',
          amount: amount,
        ),
      ],
    );
    var row = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).last;
    if (customerId != null || dealerId != null || mappedAccountId != null) {
      row = await receipts.updateReceipt(
        updated: row.copyWith(
          customerId: customerId,
          dealerId: dealerId,
          mappedAccountId: mappedAccountId,
        ),
        changedBy: 'setup',
      );
    }
    return entry.markEntered(id: row.id, enteredBy: 'clerk');
  }

  test('schema migrates to v6 with reconciliation_cases', () async {
    expect(DbSchema.version, 7);
    final db = await harness.database.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = [for (final t in tables) t['name'] as String];
    expect(names.contains(DbSchema.reconciliationCases), isTrue);
    final info = await db.rawQuery('PRAGMA table_info(receipts)');
    final cols = [for (final c in info) c['name'] as String];
    expect(cols.contains('reconciliation_completed_at'), isTrue);
  });

  test('amount correction 700000 → 70000 after Entered', () async {
    final entered = await seedEntered(amount: 700000, prefix: 'AMT');
    final enteredAt = entered.enteredAt;

    expect(
      () => entry.applyFinancialEdit(
        id: entered.id,
        newAmount: 70000,
        changedBy: 'clerk',
      ),
      throwsStateError,
    );

    final updated = await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 70000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );

    expect(updated.amount, 70000);
    expect(updated.priorAmount, 700000);
    expect(updated.entryStatus, DbEntryStatus.entered);
    expect(updated.enteredAt, enteredAt);
    expect(updated.reviewStatus, DbReviewStatus.needsReconciliation);

    final cases = await entry.listCasesForReceipt(entered.id);
    expect(cases, hasLength(1));
    expect(cases.single.previousAmount, 700000);
    expect(cases.single.correctedAmount, 70000);
    expect(cases.single.status, ReconciliationCaseStatus.open);

    final audits = await receipts.listAuditHistory(entered.id);
    expect(audits.any((a) => a.fieldName == 'amount'), isTrue);
    expect(audits.any((a) => a.fieldName == 'reconciliation_case'), isTrue);
  });

  test('date, customer, dealer, office account corrections', () async {
    final customers = CustomerRepository(harness.database);
    final dealers = DealerRepository(harness.database);
    final custA = await customers.create(name: 'Customer A');
    final custB = await customers.create(name: 'Customer B');
    final dealer = await dealers.create(name: 'Dealer One');

    final entered = await seedEntered(
      prefix: 'FLD',
      customerId: custA.id,
      mappedAccountId: DefaultOfficeAccountIds.mutalib,
    );

    final dateFixed = await entry.applyFinancialEdit(
      id: entered.id,
      newAccountingDate: DateTime(2026, 10, 9),
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    expect(dateFixed.accountingDate, DateTime.utc(2026, 10, 9));
    expect(dateFixed.reviewStatus, DbReviewStatus.needsReconciliation);

    await entry.confirmReconciliationReviewed(
      id: entered.id,
      reviewedBy: 'clerk',
    );

    final customerFixed = await entry.applyFinancialEdit(
      id: entered.id,
      newCustomerId: custB.id,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    expect(customerFixed.customerId, custB.id);

    await entry.confirmReconciliationReviewed(
      id: entered.id,
      reviewedBy: 'clerk',
    );

    final dealerFixed = await entry.applyFinancialEdit(
      id: entered.id,
      newDealerId: dealer.id,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    expect(dealerFixed.dealerId, dealer.id);

    await entry.confirmReconciliationReviewed(
      id: entered.id,
      reviewedBy: 'clerk',
    );

    final officeFixed = await entry.applyFinancialEdit(
      id: entered.id,
      newMappedAccountId: DefaultOfficeAccountIds.ad,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    expect(officeFixed.mappedAccountId, DefaultOfficeAccountIds.ad);

    final directionFixed = await entry.applyFinancialEdit(
      id: entered.id,
      newReceiptType: DbReceiptType.sent,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    expect(directionFixed.receiptType, DbReceiptType.sent);

    final cases = await entry.listCasesForReceipt(entered.id);
    expect(cases.length, greaterThanOrEqualTo(5));
  });

  test('non-financial note edit does not trigger reconciliation', () async {
    final entered = await seedEntered(prefix: 'NOTE');
    final updated = await entry.applyFinancialEdit(
      id: entered.id,
      newNotes: 'harmless desk note',
      newAdminMessage: 'updated admin chatter',
      changedBy: 'clerk',
    );
    expect(updated.reviewStatus, isNot(DbReviewStatus.needsReconciliation));
    expect(updated.entryStatus, DbEntryStatus.entered);
    expect(updated.notes, 'harmless desk note');
    expect(await entry.listCasesForReceipt(entered.id), isEmpty);
  });

  test('cancelled edit leaves data unchanged', () async {
    final entered = await seedEntered(amount: 700000, prefix: 'CAN');
    // UI cancel = never call apply. Service rejects unconfirmed financial edit.
    expect(
      () => entry.applyFinancialEdit(
        id: entered.id,
        newAmount: 70000,
        changedBy: 'clerk',
        userConfirmedReconciliation: false,
      ),
      throwsStateError,
    );
    final still = await receipts.getById(entered.id);
    expect(still!.amount, 700000);
    expect(still.reviewStatus, isNot(DbReviewStatus.needsReconciliation));
  });

  test('multiple corrections keep immutable case history', () async {
    final entered = await seedEntered(amount: 700000, prefix: 'MULTI');
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 70000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 75000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    final cases = await entry.listCasesForReceipt(entered.id);
    expect(cases, hasLength(2));
    expect(cases[0].previousAmount, 700000);
    expect(cases[0].correctedAmount, 70000);
    expect(cases[1].previousAmount, 70000);
    expect(cases[1].correctedAmount, 75000);
    expect(cases[0].id, isNot(cases[1].id));
  });

  test('complete reconciliation returns Entered with timestamp', () async {
    final entered = await seedEntered(amount: 700000, prefix: 'DONE');
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 70000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    final done = await entry.confirmReconciliationReviewed(
      id: entered.id,
      reviewedBy: 'clerk',
      correctionNotes: 'Corrected in WinForms',
    );
    expect(done.reviewStatus, DbReviewStatus.approved);
    expect(done.entryStatus, DbEntryStatus.entered);
    expect(done.reconciliationCompletedAt, isNotNull);
    expect(done.enteredAt, isNotNull);

    final cases = await entry.listCasesForReceipt(entered.id);
    expect(
      cases.every((c) => c.status == ReconciliationCaseStatus.completed),
      isTrue,
    );
    expect(cases.first.correctionNotes, 'Corrected in WinForms');
  });

  test('reopen reconciliation creates audit case', () async {
    final entered = await seedEntered(prefix: 'REOPEN');
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 1,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    await entry.confirmReconciliationReviewed(
      id: entered.id,
      reviewedBy: 'clerk',
    );
    final reopened = await entry.reopenReconciliation(
      id: entered.id,
      reopenedBy: 'clerk',
    );
    expect(reopened.reviewStatus, DbReviewStatus.needsReconciliation);
    expect(reopened.reconciliationCompletedAt, isNull);
    final cases = await entry.listCasesForReceipt(entered.id);
    expect(
      cases.any((c) => c.kind == ReconciliationCaseKind.reopen && c.isOpen),
      isTrue,
    );
  });

  test('delete and restore keep reconciliation requirement', () async {
    final entered = await seedEntered(prefix: 'DEL');
    await entry.requestDeleteReviewForEntered(
      id: entered.id,
      changedBy: 'clerk',
    );
    await entry.softDeleteAfterReview(id: entered.id, changedBy: 'clerk');
    expect(await receipts.getById(entered.id), isNull);

    final deleted = await receipts.getById(entered.id, includeDeleted: true);
    expect(deleted!.deletedAt, isNotNull);
    expect(deleted.reviewStatus, DbReviewStatus.needsReconciliation);
    expect(deleted.entryStatus, DbEntryStatus.entered);

    final cases = await entry.listCasesForReceipt(entered.id);
    expect(cases.any((c) => c.kind == ReconciliationCaseKind.deletion), isTrue);

    final restored = await receipts.restore(id: entered.id, changedBy: 'clerk');
    expect(restored.deletedAt, isNull);
    expect(restored.reviewStatus, DbReviewStatus.needsReconciliation);
    expect(restored.entryStatus, DbEntryStatus.entered);
    expect(restored.enteredAt, isNotNull);
  });

  test('app restart preserves reconciliation cases', () async {
    final entered = await seedEntered(amount: 700000, prefix: 'RST');
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 70000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    await harness.reopen();
    receipts = harness.receipts;
    entry = ReceiptEntryService(receipts);
    final again = await receipts.getById(entered.id);
    expect(again!.amount, 70000);
    expect(again.priorAmount, 700000);
    expect(again.reviewStatus, DbReviewStatus.needsReconciliation);
    expect(await entry.listCasesForReceipt(entered.id), hasLength(1));
  });

  test('new import never resets existing reconciliation status', () async {
    final entered = await seedEntered(amount: 700000, prefix: 'IMP');
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 70000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'evening',
      drafts: [harness.draft(transactionId: 'IMP_NEW', amount: 100)],
    );
    final still = await receipts.getById(entered.id);
    expect(still!.reviewStatus, DbReviewStatus.needsReconciliation);
    expect(still.amount, 70000);
    expect(still.entryStatus, DbEntryStatus.entered);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 2);
  });

  test('financial detector ignores notes-only patches', () {
    final sample = ReceiptRecord(
      id: 'x',
      bankName: 'HBL',
      amount: 100,
      currency: 'PKR',
      accountingDate: DateTime.utc(2026, 10, 10),
      importedAt: DateTime.utc(2026, 10, 10),
      receiptType: DbReceiptType.received,
      reviewStatus: DbReviewStatus.approved,
      entryStatus: DbEntryStatus.entered,
      createdAt: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 10),
    );
    expect(
      FinancialChangeDetector.isFinancialChange(
        sample,
        const ReceiptFinancialPatch(notes: 'n', adminMessage: 'a'),
      ),
      isFalse,
    );
    expect(
      FinancialChangeDetector.isFinancialChange(
        sample,
        const ReceiptFinancialPatch(amount: 50),
      ),
      isTrue,
    );
  });
}
