import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/desk/receipt_entry_service.dart';
import 'package:ai_bank_receipt_manager/core/formatting/account_mask.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_crypto.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_service.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late ReceiptRepository receipts;
  late ReceiptEntryService entry;
  late BackupService backup;

  BackupService makeBackup() => BackupService(
    paths: harness.paths,
    database: harness.database,
    crypto: BackupCrypto(iterations: 1000),
  );

  setUp(() async {
    harness = await TestDbHarness.create();
    receipts = harness.receipts;
    entry = ReceiptEntryService(receipts);
    backup = makeBackup();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<void> seedRichDataset() async {
    final day = DateTime(2026, 10, 10);
    final imageFile = File(harness.imagePath('ticket.jpg'));
    imageFile.writeAsBytesSync(List<int>.filled(32, 7));

    final customers = CustomerRepository(harness.database);
    final dealers = DealerRepository(harness.database);
    final settings = AppSettingsRepository(harness.database);
    final customer = await customers.create(name: 'Phase9 Customer');
    final dealer = await dealers.create(name: 'Phase9 Dealer');
    await settings.set('desk.default_view', 'pending');

    await receipts.appendImport(
      accountingDate: day,
      source: 'phase9',
      drafts: [
        ReceiptImportDraft(
          transactionId: 'P9-ENTERED',
          bankName: 'HBL',
          amount: 700000,
          imageHash: sha256HexOfString('ticket'),
          originalImagePath: imageFile.path,
          bankSenderName: 'Sender 12345678901234',
          bankReceiverName: 'Recv 98765432109876',
        ),
        harness.draft(transactionId: 'P9-PENDING', amount: 1500),
      ],
    );

    final rows = await receipts.listByAccountingDate(day);
    final enteredRow = rows.firstWhere((r) => r.transactionId == 'P9-ENTERED');
    await receipts.updateReceipt(
      updated: enteredRow.copyWith(
        customerId: customer.id,
        dealerId: dealer.id,
      ),
      changedBy: 'setup',
    );
    final entered = await entry.markEntered(
      id: enteredRow.id,
      enteredBy: 'clerk',
    );
    await entry.applyFinancialEdit(
      id: entered.id,
      newAmount: 70000,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );
  }

  test('maskAccountNumber hides digit runs in ordinary UI', () {
    expect(maskAccountNumber('12345678901234'), '**********1234');
    expect(
      maskAccountNumber('Ali 12345678901234 Khan'),
      'Ali **********1234 Khan',
    );
    expect(maskAccountNumber('short'), 'short');
    expect(containsAccountNumber('12345678901234'), isTrue);
  });

  test(
    'full backup includes schema version, size, integrity, no API keys',
    () async {
      await seedRichDataset();
      final db = await harness.database.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(DbSchema.groqConfigs, {
        'id': 'cfg-test',
        'label': 'Test Key',
        'endpoint': 'https://api.groq.com/openai/v1/chat/completions',
        'model_hint': 'meta-llama/llama-4-scout-17b-16e-instruct',
        'secure_key_slot': 'slot_test',
        'is_active': 0,
        'is_enabled': 1,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      });

      final result = await backup.createFullBackup();
      expect(result.verified, isTrue);
      expect(File(result.archivePath).existsSync(), isTrue);
      expect(result.manifest.schemaVersion, DbSchema.version);
      expect(result.manifest.archiveFormatVersion, 2);
      expect(result.manifest.fileSizeBytes, greaterThan(0));
      expect(result.manifest.includesApiKeys, isFalse);
      expect(result.manifest.receiptCount, 2);
      expect(result.manifest.enteredCount, 1);
      expect(result.manifest.pendingCount, 1);
      expect(result.manifest.reconciliationCaseCount, 1);
      expect(result.manifest.imageCount, 1);
      expect(result.manifest.contentSha256, isNotEmpty);

      final preview = await backup.inspectArchive(result.archivePath);
      expect(preview.integrityOk, isTrue);

      final zipBytes = File(result.archivePath).readAsBytesSync();
      final text = utf8.decode(zipBytes, allowMalformed: true);
      expect(text.contains('gsk_'), isFalse);
      expect(text.toLowerCase().contains('api_key_value'), isFalse);
      expect(result.manifest.includesApiKeys, isFalse);
    },
  );

  test('restore to clean installation preserves UUIDs, ticks, recon', () async {
    await seedRichDataset();
    final before = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    final entered = before.firstWhere((r) => r.transactionId == 'P9-ENTERED');
    final enteredAt = entered.enteredAt;
    final uuid = entered.id;
    final cases = await entry.listCasesForReceipt(entered.id);
    expect(cases, hasLength(1));
    final caseId = cases.single.id;

    final exported = await backup.createFullBackup();
    expect(exported.verified, isTrue);

    // Simulate clean install: wipe live data.
    await harness.database.close();
    File(harness.paths.databaseFilePath).deleteSync();
    final images = Directory(harness.paths.imagesDirectoryPath);
    if (images.existsSync()) {
      images.deleteSync(recursive: true);
    }
    images.createSync(recursive: true);
    await harness.reopen();
    backup = makeBackup();
    expect(
      await harness.receipts.countByAccountingDate(DateTime(2026, 10, 10)),
      0,
    );

    final restored = await backup.restoreFromArchive(
      archivePath: exported.archivePath,
      confirmReplace: true,
    );
    expect(restored.restored, isTrue);
    expect(restored.verifiedCounts, isTrue);
    expect(File(restored.safetyBackupPath).existsSync(), isTrue);

    await harness.reopen();
    receipts = harness.receipts;
    entry = ReceiptEntryService(receipts);
    final after = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    expect(after, hasLength(2));
    final restoredEntered = after.firstWhere(
      (r) => r.transactionId == 'P9-ENTERED',
    );
    expect(restoredEntered.id, uuid);
    expect(restoredEntered.entryStatus, DbEntryStatus.entered);
    expect(restoredEntered.enteredAt, enteredAt);
    expect(restoredEntered.amount, 70000);

    final restoredCases = await entry.listCasesForReceipt(uuid);
    expect(restoredCases, hasLength(1));
    expect(restoredCases.single.id, caseId);

    final settings = AppSettingsRepository(harness.database);
    expect(await settings.get('desk.default_view'), 'pending');

    final imageFile = File(harness.imagePath('ticket.jpg'));
    expect(imageFile.existsSync(), isTrue);
  });

  test('encrypted backup wrong password fails; correct restores', () async {
    await seedRichDataset();
    final exported = await backup.createFullBackup(password: 'secret99');
    expect(exported.archivePath.endsWith('.aibackup'), isTrue);
    expect(exported.manifest.encrypted, isTrue);
    expect(
      BackupCrypto.looksEncrypted(File(exported.archivePath).readAsBytesSync()),
      isTrue,
    );

    final bad = await backup.inspectArchive(
      exported.archivePath,
      password: 'wrong-password',
    );
    expect(bad.integrityOk, isFalse);
    expect(bad.integrityError, contains('Wrong backup password'));

    await expectLater(
      backup.restoreFromArchive(
        archivePath: exported.archivePath,
        confirmReplace: true,
        password: 'wrong-password',
      ),
      throwsA(isA<StateError>()),
    );

    final good = await backup.inspectArchive(
      exported.archivePath,
      password: 'secret99',
    );
    expect(good.integrityOk, isTrue);

    await harness.reopen();
    backup = makeBackup();
    await harness.receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'noise',
      drafts: [harness.draft(transactionId: 'NOISE')],
    );
    final restored = await backup.restoreFromArchive(
      archivePath: exported.archivePath,
      confirmReplace: true,
      password: 'secret99',
    );
    expect(restored.restored, isTrue);
    await harness.reopen();
    expect(
      await harness.receipts.countByAccountingDate(DateTime(2026, 10, 10)),
      2,
    );
  });

  test('corrupt backup fails archive validation', () async {
    await seedRichDataset();
    final exported = await backup.createFullBackup();
    final file = File(exported.archivePath);
    final bytes = file.readAsBytesSync();
    bytes[bytes.length ~/ 2] ^= 0xFF;
    file.writeAsBytesSync(bytes);

    await harness.reopen();
    backup = makeBackup();
    final preview = await backup.inspectArchive(exported.archivePath);
    expect(preview.integrityOk, isFalse);

    await expectLater(
      backup.restoreFromArchive(
        archivePath: exported.archivePath,
        confirmReplace: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('failed restore verification reinstates safety backup', () async {
    await seedRichDataset();
    final liveBefore = await receipts.countByAccountingDate(
      DateTime(2026, 10, 10),
    );
    expect(liveBefore, 2);

    final exported = await backup.createFullBackup();
    final tampered = p.join(harness.root.path, 'tampered.zip');
    await _rewriteManifestCounts(
      sourceZip: exported.archivePath,
      targetZip: tampered,
      receiptCount: 999,
    );

    await harness.reopen();
    backup = makeBackup();
    await expectLater(
      backup.restoreFromArchive(archivePath: tampered, confirmReplace: true),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Restore verification failed'),
        ),
      ),
    );

    await harness.reopen();
    expect(
      await harness.receipts.countByAccountingDate(DateTime(2026, 10, 10)),
      liveBefore,
    );
    expect(
      (await harness.receipts.listByAccountingDate(
        DateTime(2026, 10, 10),
      )).map((r) => r.transactionId),
      containsAll(['P9-ENTERED', 'P9-PENDING']),
    );
  });

  test('missing image handling reports missing count', () async {
    await seedRichDataset();
    final exported = await backup.createFullBackup();
    final stripped = p.join(harness.root.path, 'no_images.zip');
    await _stripImagesFromZip(exported.archivePath, stripped);

    await harness.reopen();
    backup = makeBackup();
    // Change live so restore actually replaces.
    await harness.receipts.appendImport(
      accountingDate: DateTime(2026, 10, 11),
      source: 'other',
      drafts: [harness.draft(transactionId: 'OTHER')],
    );

    final restored = await backup.restoreFromArchive(
      archivePath: stripped,
      confirmReplace: true,
    );
    expect(restored.restored, isTrue);
    expect(restored.missingImageCount, greaterThan(0));
  });

  test(
    'app upgrade: older schema backup restores; newer schema refused',
    () async {
      await seedRichDataset();
      final exported = await backup.createFullBackup();
      expect(
        exported.manifest.schemaVersion,
        lessThanOrEqualTo(DbSchema.version),
      );

      final older = p.join(harness.root.path, 'older_schema.zip');
      await _rewriteManifestSchema(
        sourceZip: exported.archivePath,
        targetZip: older,
        schemaVersion: 1,
      );
      await harness.reopen();
      backup = makeBackup();
      final olderPreview = await backup.inspectArchive(older);
      expect(olderPreview.integrityOk, isTrue);
      final restored = await backup.restoreFromArchive(
        archivePath: older,
        confirmReplace: true,
      );
      expect(restored.restored, isTrue);

      final newer = p.join(harness.root.path, 'newer_schema.zip');
      await _rewriteManifestSchema(
        sourceZip: exported.archivePath,
        targetZip: newer,
        schemaVersion: DbSchema.version + 5,
      );
      await harness.reopen();
      backup = makeBackup();
      await expectLater(
        backup.restoreFromArchive(archivePath: newer, confirmReplace: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('newer than'),
          ),
        ),
      );
    },
  );

  test('restore requires confirmation', () async {
    await seedRichDataset();
    final exported = await backup.createFullBackup();
    await harness.reopen();
    backup = makeBackup();
    await expectLater(
      backup.restoreFromArchive(
        archivePath: exported.archivePath,
        confirmReplace: false,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _rewriteManifestCounts({
  required String sourceZip,
  required String targetZip,
  required int receiptCount,
}) async {
  final decoded = ZipDecoder().decodeBytes(File(sourceZip).readAsBytesSync());
  final archive = Archive();
  for (final file in decoded.files) {
    if (!file.isFile) {
      continue;
    }
    if (file.name == 'manifest.json') {
      final json = Map<String, Object?>.from(
        jsonDecode(utf8.decode(file.content as List<int>)) as Map,
      );
      json['receiptCount'] = receiptCount;
      final bytes = utf8.encode(jsonEncode(json));
      archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    } else {
      final content = file.content as List<int>;
      archive.addFile(ArchiveFile(file.name, content.length, content));
    }
  }
  final encoded = ZipEncoder().encode(archive)!;
  File(targetZip).writeAsBytesSync(Uint8List.fromList(encoded));
}

Future<void> _rewriteManifestSchema({
  required String sourceZip,
  required String targetZip,
  required int schemaVersion,
}) async {
  final decoded = ZipDecoder().decodeBytes(File(sourceZip).readAsBytesSync());
  final archive = Archive();
  for (final file in decoded.files) {
    if (!file.isFile) {
      continue;
    }
    if (file.name == 'manifest.json') {
      final json = Map<String, Object?>.from(
        jsonDecode(utf8.decode(file.content as List<int>)) as Map,
      );
      json['schemaVersion'] = schemaVersion;
      final bytes = utf8.encode(jsonEncode(json));
      archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    } else {
      final content = file.content as List<int>;
      archive.addFile(ArchiveFile(file.name, content.length, content));
    }
  }
  final encoded = ZipEncoder().encode(archive)!;
  File(targetZip).writeAsBytesSync(Uint8List.fromList(encoded));
}

Future<void> _stripImagesFromZip(String sourceZip, String targetZip) async {
  final decoded = ZipDecoder().decodeBytes(File(sourceZip).readAsBytesSync());
  final archive = Archive();
  final hashParts = <String>[];
  for (final file in decoded.files) {
    if (!file.isFile) {
      continue;
    }
    if (file.name.startsWith('receipt_images/')) {
      continue;
    }
    if (file.name == 'manifest.json') {
      continue;
    }
    final content = file.content as List<int>;
    archive.addFile(ArchiveFile(file.name, content.length, content));
    if (file.name == DbSchema.databaseName) {
      hashParts.add(sha256Hex(content));
    }
  }
  final contentSha256 = sha256HexOfString(hashParts.join('|'));
  final manifest = {
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'databaseFileName': DbSchema.databaseName,
    'imageCount': 0,
    'appName': 'AI Bank Receipt Manager',
    'schemaVersion': DbSchema.version,
    'archiveFormatVersion': 2,
    'contentSha256': contentSha256,
    'receiptCount': 2,
    'customerCount': 1,
    'dealerCount': 1,
    'officeAccountCount': 2,
    'auditCount': 0,
    'reconciliationCaseCount': 1,
    'importBatchCount': 1,
    'enteredCount': 1,
    'pendingCount': 1,
    'includesApiKeys': false,
    'encrypted': false,
  };
  // Re-read real counts from source manifest for non-image fields.
  final sourceManifest = decoded.findFile('manifest.json');
  if (sourceManifest != null && sourceManifest.isFile) {
    final json = Map<String, Object?>.from(
      jsonDecode(utf8.decode(sourceManifest.content as List<int>)) as Map,
    );
    for (final key in [
      'receiptCount',
      'customerCount',
      'dealerCount',
      'officeAccountCount',
      'auditCount',
      'reconciliationCaseCount',
      'importBatchCount',
      'enteredCount',
      'pendingCount',
      'schemaVersion',
    ]) {
      final value = json[key];
      if (value != null) {
        manifest[key] = value;
      }
    }
  }
  manifest['imageCount'] = 0;
  manifest['contentSha256'] = contentSha256;
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  archive.addFile(
    ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
  );
  final encoded = ZipEncoder().encode(archive)!;
  File(targetZip).writeAsBytesSync(Uint8List.fromList(encoded));
}
