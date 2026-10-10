import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/groq/groq_key_manager.dart';
import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/import/batch_import_service.dart';
import 'package:ai_bank_receipt_manager/application/import/receipt_ingestion.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/import_queue_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late MemorySecureKeyStore store;
  late ImportQueueRepository queue;
  late ReceiptRepository receipts;
  late BatchImportService batchService;
  late ControllableIngestionSource shareSource;

  setUp(() async {
    harness = await TestDbHarness.create();
    store = MemorySecureKeyStore();
    queue = ImportQueueRepository(harness.database);
    receipts = ReceiptRepository(harness.database);
    shareSource = ControllableIngestionSource();

    final client = GroqVisionClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'bankName': 'HBL',
                    'amount': 2500,
                    'currency': 'PKR',
                    'transactionReference': 'REF-${request.hashCode}',
                    'adminMessage': 'Customer Ali',
                    'whatsappSender': 'Office Desk',
                  }),
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final configs = GroqApiConfigurationRepository(harness.database);
    final keys = GroqKeyManager(
      configs: configs,
      keyStore: store,
      client: client,
    );
    await keys.addKey(label: 'T', apiKey: 'gsk_test_key_phase5_hhhhhhhh');

    final vision = ReceiptVisionService(
      keyManager: keys,
      configs: configs,
      extractions: AiExtractionRepository(harness.database),
      receipts: receipts,
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
      client: client,
    );

    batchService = BatchImportService(
      queue: queue,
      receipts: receipts,
      vision: vision,
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
      maxConcurrent: 1,
    );
  });

  tearDown(() async {
    await shareSource.dispose();
    await harness.dispose();
  });

  Future<File> makeImage(String name) async {
    final file = File('${harness.paths.imagesDirectoryPath}/$name');
    await file.writeAsBytes(List<int>.generate(48, (i) => i + name.hashCode));
    return file;
  }

  Future<BatchItemReviewOutcome?> autoAccept(
    ImportQueueItemRecord item,
    VisionJobResult? vision,
    List<DuplicateMatch> duplicates,
  ) async {
    if (duplicates.isNotEmpty) {
      return BatchItemReviewOutcome(
        extraction: vision?.extraction ?? const ReceiptExtraction(),
        duplicateDecision: DuplicateDecision.keepSeparate,
        duplicateOfReceiptId: duplicates.first.existing.id,
      );
    }
    return BatchItemReviewOutcome(
      extraction:
          vision?.extraction ??
          const ReceiptExtraction(
            bankName: 'HBL',
            amount: 1,
            currency: 'PKR',
          ),
      adminMessage: item.adminNoteOverride ?? vision?.extraction?.adminMessage,
    );
  }

  test('schema v4 has import queue table', () async {
    expect(DbSchema.version, 6);
    final db = await harness.database.database;
    final info = await db.rawQuery(
      'PRAGMA table_info(${DbSchema.importQueueItems})',
    );
    expect(info, isNotEmpty);
  });

  test('1 single image import creates batch counts', () async {
    final image = await makeImage('one.jpg');
    final batch = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [
        IngestedFile(path: image.path, sourceKind: 'gallery'),
      ],
    );
    expect(batch.fileCount, 1);
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    final done = await queue.getBatch(batch.id);
    expect(done!.successCount, 1);
    expect(done.failedCount, 0);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 1);
  });

  test('2 multiple images append in one batch', () async {
    final a = await makeImage('a.jpg');
    final b = await makeImage('b.jpg');
    final batch = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [
        IngestedFile(path: a.path, sourceKind: 'gallery'),
        IngestedFile(path: b.path, sourceKind: 'gallery'),
      ],
    );
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    final done = await queue.getBatch(batch.id);
    expect(done!.fileCount, 2);
    expect(done.successCount, 2);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 2);
  });

  test('3 shared WhatsApp image uses ingestion source pipeline', () async {
    final image = await makeImage('wa.jpg');
    shareSource.setInitial([
      IngestedFile(
        path: image.path,
        sourceKind: 'android_share',
        displayName: 'wa.jpg',
      ),
    ]);
    final shared = await shareSource.getInitialFiles();
    final batch = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'android_share',
      files: shared,
    );
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    final items = await queue.listForBatch(batch.id);
    expect(items.single.sourceKind, 'android_share');
    expect(items.single.queueStatus, ImportQueueStatus.succeeded);
  });

  test('4 screenshot with caption / admin note preserved', () async {
    final image = await makeImage('caption.jpg');
    final batch = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      sharedAdminNote: 'Dealer Farhan AD',
      files: [IngestedFile(path: image.path, sourceKind: 'gallery')],
    );
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    final listed = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    expect(listed.single.adminMessage, contains('Farhan'));
  });

  test('5 duplicate import can be skipped', () async {
    final bytes = Uint8List.fromList(List<int>.filled(32, 7));
    final image = File('${harness.paths.imagesDirectoryPath}/dup.jpg');
    await image.writeAsBytes(bytes);

    final first = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [IngestedFile(path: image.path, sourceKind: 'gallery')],
    );
    await batchService.processQueued(
      batchId: first.id,
      onNeedsReview: autoAccept,
    );

    final secondImage = File('${harness.paths.imagesDirectoryPath}/dup2.jpg');
    await secondImage.writeAsBytes(bytes);
    final second = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [IngestedFile(path: secondImage.path, sourceKind: 'gallery')],
    );
    await batchService.processQueued(
      batchId: second.id,
      onNeedsReview: (item, vision, duplicates) async {
        expect(duplicates, isNotEmpty);
        return BatchItemReviewOutcome(
          extraction: vision!.extraction!,
          duplicateDecision: DuplicateDecision.skip,
          duplicateOfReceiptId: duplicates.first.existing.id,
        );
      },
    );
    final done = await queue.getBatch(second.id);
    expect(done!.duplicateCount, 1);
    expect(done.successCount, 0);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 1);
  });

  test('6 historical import uses selected accounting date', () async {
    final image = await makeImage('hist.jpg');
    final yesterday = DateTime(2026, 10, 9);
    final batch = await batchService.enqueueFiles(
      accountingDate: yesterday,
      source: 'gallery',
      files: [IngestedFile(path: image.path, sourceKind: 'gallery')],
    );
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    expect(await receipts.countByAccountingDate(yesterday), 1);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 0);
    final row = (await receipts.listByAccountingDate(yesterday)).single;
    expect(row.accountingDate.day, 9);
    expect(row.importedAt.isAfter(row.accountingDate), isTrue);
  });

  test('7 network failure during batch preserves image and allows retry', () async {
    final failingClient = GroqVisionClient(
      httpClient: MockClient((request) async {
        throw const SocketException('Failed host lookup');
      }),
    );
    final configs = GroqApiConfigurationRepository(harness.database);
    final keys = GroqKeyManager(
      configs: configs,
      keyStore: store,
      client: failingClient,
    );
    final vision = ReceiptVisionService(
      keyManager: keys,
      configs: configs,
      extractions: AiExtractionRepository(harness.database),
      receipts: receipts,
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
      client: failingClient,
    );
    final failingBatch = BatchImportService(
      queue: queue,
      receipts: receipts,
      vision: vision,
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
    );

    final image = await makeImage('net.jpg');
    final batch = await failingBatch.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [IngestedFile(path: image.path, sourceKind: 'gallery')],
    );
    await failingBatch.processQueued(
      batchId: batch.id,
      onNeedsReview: (item, visionResult, duplicates) async {
        // Vision failed but file exists — manual save path.
        expect(File(item.storedPath).existsSync(), isTrue);
        return BatchItemReviewOutcome(
          extraction: const ReceiptExtraction(
            bankName: 'UBL',
            amount: 100,
            currency: 'PKR',
            transactionReference: 'MANUAL-NET',
          ),
        );
      },
    );
    final item = (await queue.listForBatch(batch.id)).single;
    expect(File(item.storedPath).existsSync(), isTrue);
    expect(item.queueStatus, ImportQueueStatus.succeeded);
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 1);
  });

  test('8 app restart mid-queue resumes failed/queued items', () async {
    final image = await makeImage('resume.jpg');
    final batch = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [IngestedFile(path: image.path, sourceKind: 'gallery')],
    );
    final item = (await queue.listForBatch(batch.id)).single;
    expect(item.queueStatus, ImportQueueStatus.queued);

    await harness.reopen();
    queue = ImportQueueRepository(harness.database);
    receipts = ReceiptRepository(harness.database);

    final client = GroqVisionClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'bankName': 'MCB',
                    'amount': 50,
                    'currency': 'PKR',
                    'transactionReference': 'RESUMED',
                  }),
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    final configs = GroqApiConfigurationRepository(harness.database);
    final keys = GroqKeyManager(
      configs: configs,
      keyStore: store,
      client: client,
    );
    final vision = ReceiptVisionService(
      keyManager: keys,
      configs: configs,
      extractions: AiExtractionRepository(harness.database),
      receipts: receipts,
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
      client: client,
    );
    batchService = BatchImportService(
      queue: queue,
      receipts: receipts,
      vision: vision,
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
    );

    final pending = await queue.listByStatus(ImportQueueStatus.queued);
    expect(pending, isNotEmpty);
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    final done = await queue.getBatch(batch.id);
    expect(done!.successCount, 1);
  });

  test('9 midday + evening batches keep entered statuses', () async {
    final morning = await makeImage('m.jpg');
    final b1 = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [IngestedFile(path: morning.path, sourceKind: 'gallery')],
    );
    await batchService.processQueued(batchId: b1.id, onNeedsReview: autoAccept);
    final first = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).single;
    await receipts.markEntered(id: first.id, enteredBy: 'desk');

    final evening = await makeImage('e.jpg');
    final b2 = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [IngestedFile(path: evening.path, sourceKind: 'gallery')],
    );
    await batchService.processQueued(batchId: b2.id, onNeedsReview: autoAccept);

    final all = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    expect(all, hasLength(2));
    final stillEntered = all.firstWhere((r) => r.id == first.id);
    expect(stillEntered.entryStatus, DbEntryStatus.entered);
    expect(stillEntered.amount, first.amount);
  });

  test('manual entry and admin note edit', () async {
    final saved = await batchService.saveManualEntry(
      accountingDate: DateTime(2026, 10, 10),
      fields: const ReceiptExtraction(
        bankName: 'Alfalah',
        amount: 300,
        currency: 'PKR',
        transactionReference: 'MAN-1',
      ),
      adminMessage: 'Customer Zain',
    );
    expect(saved.adminMessage, 'Customer Zain');
    final updated = await batchService.updateAdminNote(
      receiptId: saved.id,
      adminMessage: 'Customer Zain Mutalib',
    );
    expect(updated.adminMessage, contains('Mutalib'));
  });

  test('grouped multi-image one transaction yields one receipt', () async {
    final a = await makeImage('g1.jpg');
    final b = await makeImage('g2.jpg');
    final groupId = 'group-1';
    final batch = await batchService.enqueueFiles(
      accountingDate: DateTime(2026, 10, 10),
      source: 'gallery',
      files: [
        IngestedFile(path: a.path, sourceKind: 'gallery'),
        IngestedFile(path: b.path, sourceKind: 'gallery'),
      ],
      groupIdsByPath: {a.path: groupId, b.path: groupId},
    );
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: autoAccept,
    );
    expect(await receipts.countByAccountingDate(DateTime(2026, 10, 10)), 1);
    final items = await queue.listForBatch(batch.id);
    expect(items.every((i) => i.queueStatus == ImportQueueStatus.succeeded), isTrue);
  });

  test('ingestion extension interface documents empty source', () async {
    final empty = EmptyIngestionSource();
    expect(await empty.isAvailable, isFalse);
    expect(await empty.getInitialFiles(), isEmpty);
  });
}
