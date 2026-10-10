import 'dart:io';

import 'package:ai_bank_receipt_manager/data/backup/backup_service.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;

  setUp(() async {
    harness = await TestDbHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('persistence survives close and reopen (app restart)', () async {
    final day = DateTime.utc(2026, 10, 10);
    await harness.receipts.appendImport(
      accountingDate: day,
      source: 'manual',
      drafts: [harness.draft(transactionId: 'HBL-1', amount: 250000)],
    );

    await harness.reopen();

    final rows = await harness.receipts.listByAccountingDate(day);
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, 'HBL-1');
    expect(rows.single.amount, 250000);
    expect(rows.single.entryStatus, DbEntryStatus.pending);
  });

  test(
    'append import keeps earlier receipts on the same accounting date',
    () async {
      final day = DateTime.utc(2026, 10, 10);

      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'batch-1pm',
        importedAt: DateTime.utc(2026, 10, 10, 13),
        drafts: [
          for (var i = 0; i < 20; i++)
            harness.draft(transactionId: 'A-$i', amount: 1000 + i),
        ],
      );

      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'batch-8pm',
        importedAt: DateTime.utc(2026, 10, 10, 20),
        drafts: [
          for (var i = 0; i < 5; i++)
            harness.draft(transactionId: 'B-$i', amount: 2000 + i),
        ],
      );

      final rows = await harness.receipts.listByAccountingDate(day);
      expect(rows, hasLength(25));

      final batches = await ImportBatchRepository(
        harness.database,
      ).listByAccountingDate(day);
      expect(batches, hasLength(2));
      expect(batches.first.receiptCount, 20);
      expect(batches.last.receiptCount, 5);
    },
  );

  test(
    'entered statuses stay permanent when new receipts are imported',
    () async {
      final day = DateTime.utc(2026, 10, 10);
      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'initial',
        drafts: [
          for (var i = 0; i < 15; i++)
            harness.draft(transactionId: 'E-$i', amount: 5000 + i),
        ],
      );

      final first = await harness.receipts.listByAccountingDate(day);
      for (final receipt in first) {
        await harness.receipts.markEntered(id: receipt.id, enteredBy: 'desk');
      }
      expect(await harness.receipts.countEnteredByAccountingDate(day), 15);

      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'later',
        drafts: [
          harness.draft(transactionId: 'NEW-1', amount: 99),
          harness.draft(transactionId: 'NEW-2', amount: 100),
        ],
      );

      expect(await harness.receipts.countByAccountingDate(day), 17);
      expect(await harness.receipts.countEnteredByAccountingDate(day), 15);

      final stillEntered = await harness.receipts.listByAccountingDate(day);
      expect(
        stillEntered
            .where((r) => r.entryStatus == DbEntryStatus.entered)
            .length,
        15,
      );
      expect(
        stillEntered
            .where((r) => r.entryStatus == DbEntryStatus.pending)
            .length,
        2,
      );
    },
  );

  test(
    'historical import assigns today import to yesterday accounting date',
    () async {
      final yesterday = DateTime.utc(2026, 10, 9);
      final importedAt = DateTime.utc(2026, 10, 10, 16, 30);
      final txnAt = DateTime.utc(2026, 10, 9, 11, 5);
      final waAt = DateTime.utc(2026, 10, 9, 11, 10);

      await harness.receipts.appendImport(
        accountingDate: yesterday,
        importedAt: importedAt,
        source: 'historical',
        drafts: [
          ReceiptImportDraft(
            transactionId: 'HIST-1',
            bankName: 'Meezan Bank',
            amount: 180000,
            transactionDateTime: txnAt,
            whatsappMessageDateTime: waAt,
            adminMessage: 'Sara Noor to AD',
          ),
        ],
      );

      final rows = await harness.receipts.listByAccountingDate(yesterday);
      expect(rows, hasLength(1));
      expect(encodeDateOnly(rows.single.accountingDate), '2026-10-09');
      expect(rows.single.importedAt, importedAt);
      expect(rows.single.transactionDateTime, txnAt);
      expect(rows.single.whatsappMessageDateTime, waAt);
      expect(
        await harness.receipts.listByAccountingDate(DateTime.utc(2026, 10, 10)),
        isEmpty,
      );
    },
  );

  test(
    'safe edit writes audit history for amount party date notes and status',
    () async {
      final day = DateTime.utc(2026, 10, 10);
      final customer = await CustomerRepository(
        harness.database,
      ).create(name: 'Bilal Ahmed', usualAccountId: 'account-mutalib');
      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'edit-test',
        drafts: [harness.draft(transactionId: 'ED-1', amount: 40000)],
      );
      final receipt = (await harness.receipts.listByAccountingDate(day)).single;

      final updated = await harness.receipts.updateReceipt(
        updated: receipt.copyWith(
          amount: 45000,
          customerId: customer.id,
          accountingDate: DateTime.utc(2026, 10, 9),
          notes: 'Corrected amount',
          entryStatus: DbEntryStatus.entered,
          enteredAt: DateTime.utc(2026, 10, 10, 18),
          enteredBy: 'desk',
        ),
        changedBy: 'desk',
        reason: 'Manual correction before WinForms entry',
      );

      expect(updated.amount, 45000);
      final audit = await harness.receipts.listAuditHistory(receipt.id);
      final fields = audit.map((e) => e.fieldName).toSet();
      expect(
        fields,
        containsAll([
          'amount',
          'customer_id',
          'accounting_date',
          'notes',
          'entry_status',
        ]),
      );
      expect(
        audit.where((e) => e.fieldName == 'amount').single.oldValue,
        '40000.0',
      );
      expect(
        audit.where((e) => e.fieldName == 'amount').single.newValue,
        '45000.0',
      );
    },
  );

  test(
    'duplicate detection reports matches without deleting anything',
    () async {
      final day = DateTime.utc(2026, 10, 10);
      final hash = sha256HexOfString('image-bytes');
      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'dup-seed',
        drafts: [
          harness.draft(
            transactionId: 'DUP-1',
            amount: 75000,
            imageHash: hash,
            transactionDateTime: DateTime.utc(2026, 10, 10, 9),
          ),
        ],
      );

      final matches = await harness.receipts.findPossibleDuplicates(
        harness.draft(
          transactionId: 'DUP-1',
          amount: 75000,
          imageHash: hash,
          transactionDateTime: DateTime.utc(2026, 10, 10, 9),
        ),
        accountingDate: day,
      );

      expect(matches, isNotEmpty);
      expect(matches.first.reasons, contains('transaction_id'));
      expect(matches.first.reasons, contains('image_hash'));
      expect(await harness.receipts.countByAccountingDate(day), 1);
    },
  );

  test('soft delete hide restore and permanent delete confirmation', () async {
    final day = DateTime.utc(2026, 10, 10);
    await harness.receipts.appendImport(
      accountingDate: day,
      source: 'delete-test',
      drafts: [harness.draft(transactionId: 'DEL-1')],
    );
    final id = (await harness.receipts.listByAccountingDate(day)).single.id;

    await harness.receipts.softDelete(id: id, changedBy: 'desk');
    expect(await harness.receipts.listByAccountingDate(day), isEmpty);
    expect(await harness.receipts.getById(id, includeDeleted: true), isNotNull);

    await harness.receipts.restore(id: id, changedBy: 'desk');
    expect(await harness.receipts.listByAccountingDate(day), hasLength(1));

    await expectLater(
      harness.receipts.permanentlyDelete(id: id, confirmPermanentDelete: false),
      throwsA(isA<StateError>()),
    );
    expect(await harness.receipts.getById(id), isNotNull);

    await harness.receipts.permanentlyDelete(
      id: id,
      confirmPermanentDelete: true,
    );
    expect(await harness.receipts.getById(id, includeDeleted: true), isNull);
  });

  test('startup and upgrade never wipe existing receipts', () async {
    final day = DateTime.utc(2026, 10, 8);
    await harness.receipts.appendImport(
      accountingDate: day,
      source: 'migration-seed',
      drafts: [harness.draft(transactionId: 'MIG-1', amount: 10)],
    );

    // Simulate an app restart with the same schema version.
    await harness.reopen();
    expect(await harness.receipts.countByAccountingDate(day), 1);

    // Simulate an additive upgrade on the live file without reset.
    final db = await harness.database.database;
    await db.execute(
      'ALTER TABLE ${DbSchema.receipts} ADD COLUMN migration_marker TEXT',
    );
    await harness.reopen();

    final rows = await harness.receipts.listByAccountingDate(day);
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, 'MIG-1');

    final accounts = await OfficeAccountRepository(harness.database).list();
    expect(accounts.map((a) => a.displayName), containsAll(['Mutalib', 'AD']));
  });

  test(
    'backup exports database and images and restore keeps safety copy',
    () async {
      final day = DateTime.utc(2026, 10, 10);
      final imageFile = File(harness.imagePath('sample.txt'));
      imageFile.writeAsStringSync('receipt-image');

      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'backup',
        drafts: [
          ReceiptImportDraft(
            transactionId: 'BK-1',
            bankName: 'HBL',
            amount: 1000,
            imageHash: sha256HexOfString('receipt-image'),
            originalImagePath: imageFile.path,
          ),
        ],
      );

      final archivePath = p.join(harness.root.path, 'exports', 'backup.zip');
      var backup = BackupService(
        paths: harness.paths,
        database: harness.database,
      );
      final exported = await backup.exportToArchive(archivePath);
      expect(File(exported.archivePath).existsSync(), isTrue);
      expect(exported.manifest.imageCount, 1);

      // Change live data, then restore the archive.
      await harness.reopen();
      backup = BackupService(paths: harness.paths, database: harness.database);
      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'after-backup',
        drafts: [harness.draft(transactionId: 'BK-2')],
      );
      expect(await harness.receipts.countByAccountingDate(day), 2);

      final restored = await backup.restoreFromArchive(
        archivePath: archivePath,
        confirmReplace: true,
      );
      expect(restored.restored, isTrue);
      expect(File(restored.safetyBackupPath).existsSync(), isTrue);

      await harness.reopen();
      final after = await harness.receipts.listByAccountingDate(day);
      expect(after, hasLength(1));
      expect(after.single.transactionId, 'BK-1');
    },
  );

  test('opening the database does not delete the existing file', () async {
    final path = harness.paths.databaseFilePath;
    expect(File(path).existsSync(), isTrue);
    final before = File(path).lengthSync();
    await harness.reopen();
    expect(File(path).existsSync(), isTrue);
    expect(File(path).lengthSync(), greaterThan(0));
    expect(File(path).lengthSync(), before);
  });
}
