import 'package:ai_bank_receipt_manager/application/desk/receipt_entry_service.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late ReceiptRepository receipts;
  late ReceiptEntryService entry;

  setUp(() async {
    harness = await TestDbHarness.create();
    receipts = ReceiptRepository(harness.database);
    entry = ReceiptEntryService(receipts);
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<void> importCount(int count, {String prefix = 'R'}) async {
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'test',
      drafts: [
        for (var i = 0; i < count; i++)
          harness.draft(
            transactionId: '$prefix-$i',
            amount: 1000 + i,
            imageHash: '$prefix-hash-$i',
          ),
      ],
    );
  }

  test('schema v5 columns exist', () async {
    expect(DbSchema.version, 5);
    final db = await harness.database.database;
    final info = await db.rawQuery('PRAGMA table_info(${DbSchema.receipts})');
    final names = info.map((r) => r['name']).toSet();
    expect(names.contains('winforms_reference'), isTrue);
    expect(names.contains('prior_amount'), isTrue);
  });

  test('20 plus 5 midday/evening scenario keeps entered ticks', () async {
    await importCount(20, prefix: 'AM');
    final morning = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    expect(morning, hasLength(20));

    for (var i = 0; i < 12; i++) {
      await entry.markEntered(id: morning[i].id, enteredBy: 'clerk');
    }

    var summary = await receipts.summarizeAccountingDate(DateTime(2026, 10, 10));
    expect(summary.totalCount, 20);
    expect(summary.enteredCount, 12);
    expect(summary.pendingCount, 8);

    await importCount(5, prefix: 'PM');
    summary = await receipts.summarizeAccountingDate(DateTime(2026, 10, 10));
    expect(summary.totalCount, 25);
    expect(summary.enteredCount, 12);
    expect(summary.pendingCount, 13);

    final all = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    expect(
      all.where((r) => r.entryStatus == DbEntryStatus.entered).length,
      12,
    );
    final stillEntered = await receipts.listFiltered(
      ReceiptListFilter(
        accountingDate: DateTime(2026, 10, 10),
        entryStatus: DbEntryStatus.entered,
      ),
    );
    expect(stillEntered, hasLength(12));
  });

  test('restart and reopen preserves entered statuses', () async {
    await importCount(3, prefix: 'RE');
    final rows = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    await entry.markEntered(id: rows.first.id, enteredBy: 'clerk');
    await harness.reopen();
    receipts = ReceiptRepository(harness.database);
    entry = ReceiptEntryService(receipts);
    final again = await receipts.getById(rows.first.id);
    expect(again!.entryStatus, DbEntryStatus.entered);
    expect(again.enteredAt, isNotNull);
  });

  test('historical receipt import on past date', () async {
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 9),
      source: 'historical',
      drafts: [harness.draft(transactionId: 'HIST-1', amount: 50)],
    );
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 9)), 1);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 0);
  });

  test('filtering by bank entry status and search', () async {
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'f',
      drafts: [
        harness.draft(transactionId: 'HBL-1', bankName: 'HBL', amount: 10),
        harness.draft(transactionId: 'UBL-1', bankName: 'UBL', amount: 20),
      ],
    );
    final hbl = await receipts.listFiltered(
      ReceiptListFilter(
        accountingDate: DateTime(2026, 10, 10),
        bankName: 'HBL',
      ),
    );
    expect(hbl, hasLength(1));
    final search = await receipts.listFiltered(
      ReceiptListFilter(
        accountingDate: DateTime(2026, 10, 10),
        searchText: 'UBL-1',
      ),
    );
    expect(search.single.bankName, 'UBL');
  });

  test('bulk status changes', () async {
    await importCount(4, prefix: 'BULK');
    final rows = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    await entry.markEnteredBulk(
      ids: rows.take(3).map((r) => r.id).toList(),
      enteredBy: 'bulk',
    );
    final summary = await receipts.summarizeAccountingDate(
      DateTime(2026, 10, 10),
    );
    expect(summary.enteredCount, 3);
    expect(summary.pendingCount, 1);
  });

  test('duplicate handling keeps both until skip decision elsewhere', () async {
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'd',
      drafts: [
        harness.draft(
          transactionId: 'DUP-1',
          amount: 99,
          imageHash: 'same-hash',
        ),
      ],
    );
    final matches = await receipts.findPossibleDuplicates(
      harness.draft(
        transactionId: 'DUP-1',
        amount: 99,
        imageHash: 'same-hash',
      ),
      accountingDate: DateTime(2026, 10, 10),
    );
    expect(matches, isNotEmpty);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 1);
  });

  test('previously entered financial edit keeps tick and needs reconciliation', () async {
    await importCount(1, prefix: 'EDIT');
    final row = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).single;
    await entry.markEntered(id: row.id, enteredBy: 'clerk');
    final updated = await entry.applyFinancialEdit(
      id: row.id,
      newAmount: 9999,
      changedBy: 'clerk',
    );
    expect(updated.entryStatus, DbEntryStatus.entered);
    expect(updated.enteredAt, isNotNull);
    expect(updated.reviewStatus, DbReviewStatus.needsReconciliation);
    expect(updated.priorAmount, row.amount);
    expect(updated.amount, 9999);

    expect(
      () => entry.markEntered(id: row.id, enteredBy: 'clerk'),
      throwsStateError,
    );
  });

  test('undo entered requires confirmation', () async {
    await importCount(1, prefix: 'UNDO');
    final row = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).single;
    await entry.markEntered(id: row.id, enteredBy: 'clerk');
    expect(
      () => entry.undoEntered(
        id: row.id,
        confirmed: false,
        changedBy: 'clerk',
      ),
      throwsStateError,
    );
    final undone = await entry.undoEntered(
      id: row.id,
      confirmed: true,
      changedBy: 'clerk',
    );
    expect(undone.entryStatus, DbEntryStatus.pending);
    expect(undone.enteredAt, isNull);
  });

  test('delete entered blocked until reconciliation review', () async {
    await importCount(1, prefix: 'DEL');
    final row = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).single;
    await entry.markEntered(id: row.id, enteredBy: 'clerk');
    expect(
      () => receipts.softDelete(id: row.id, changedBy: 'clerk'),
      throwsStateError,
    );
    await entry.requestDeleteReviewForEntered(
      id: row.id,
      changedBy: 'clerk',
    );
    final flagged = await receipts.getById(row.id);
    expect(flagged!.reviewStatus, DbReviewStatus.needsReconciliation);
    await entry.softDeleteAfterReview(id: row.id, changedBy: 'clerk');
    expect(await receipts.getById(row.id), isNull);
  });

  test('app upgrade preservation via reopen', () async {
    await importCount(2, prefix: 'UP');
    final before = await receipts.countByAccountingDate(DateTime(2026, 10, 10));
    await harness.reopen();
    receipts = ReceiptRepository(harness.database);
    expect(
      await receipts.countByAccountingDate(DateTime(2026, 10, 10)),
      before,
    );
    expect(DbSchema.version, 5);
  });

  test('move accounting date for late historical assignment', () async {
    await importCount(1, prefix: 'MOVE');
    final row = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).single;
    await receipts.moveAccountingDate(
      id: row.id,
      newAccountingDate: DateTime(2026, 10, 8),
      changedBy: 'desk',
    );
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 0);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 8)), 1);
  });
}
