import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/classification/business_classification_service.dart';
import 'package:ai_bank_receipt_manager/application/desk/receipt_entry_service.dart';
import 'package:ai_bank_receipt_manager/application/groq/groq_key_manager.dart';
import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/import/batch_import_service.dart';
import 'package:ai_bank_receipt_manager/application/import/receipt_ingestion.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_export_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_query_service.dart';
import 'package:ai_bank_receipt_manager/application/reconciliation/financial_change_detector.dart';
import 'package:ai_bank_receipt_manager/core/theme/app_theme.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_crypto.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_service.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/import_queue_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_db_harness.dart';

/// Phase 10 end-to-end production-readiness path.
///
/// Groq Vision HTTP calls are **mocked**. This suite does **not** perform a
/// live authorized Groq API integration test.
void main() {
  late TestDbHarness harness;
  late MemorySecureKeyStore keyStore;
  late ReceiptRepository receipts;
  late ReceiptEntryService entry;
  late BatchImportService batchService;
  late GroqKeyManager keys;
  late ControllableIngestionSource shareSource;
  late OfficeAccountRepository offices;
  late CustomerRepository customers;
  late DealerRepository dealers;
  late GroqApiConfigurationRepository configs;
  var visionCallCount = 0;

  final day = DateTime(2026, 10, 10);
  final yesterday = DateTime(2026, 10, 9);

  MockClient visionMock({
    required bool Function() offline,
    required bool Function() authError,
  }) {
    return MockClient((request) async {
      if (offline()) {
        throw const SocketException('Network unreachable (offline test)');
      }
      if (authError()) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Invalid API Key', 'type': 'invalid_request'},
          }),
          401,
        );
      }
      visionCallCount += 1;
      final ref = 'E2E-${visionCallCount.toString().padLeft(3, '0')}';
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'bankName': 'HBL',
                  'amount': 1000 + visionCallCount,
                  'currency': 'PKR',
                  'transactionReference': ref,
                  'senderBankAccountName': 'Customer Ali Khan',
                  'receiverBankAccountName': 'Azlan Traders',
                  'adminMessage': 'Customer Ali Mutalib received',
                  'whatsappSender': 'Office Desk',
                }),
              },
            },
          ],
        }),
        200,
      );
    });
  }

  Future<void> rebuildServices({
    bool Function()? offline,
    bool Function()? authError,
  }) async {
    final off = offline ?? () => false;
    final auth = authError ?? () => false;
    final client = GroqVisionClient(
      httpClient: visionMock(offline: off, authError: auth),
    );
    configs = GroqApiConfigurationRepository(harness.database);
    keys = GroqKeyManager(configs: configs, keyStore: keyStore, client: client);
    receipts = harness.receipts;
    entry = ReceiptEntryService(receipts);
    offices = OfficeAccountRepository(harness.database);
    customers = CustomerRepository(harness.database);
    dealers = DealerRepository(harness.database);
    batchService = BatchImportService(
      queue: ImportQueueRepository(harness.database),
      receipts: receipts,
      vision: ReceiptVisionService(
        keyManager: keys,
        configs: configs,
        extractions: AiExtractionRepository(harness.database),
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        client: client,
      ),
      imagesDirectoryPath: harness.paths.imagesDirectoryPath,
      maxConcurrent: 1,
    );
  }

  setUp(() async {
    harness = await TestDbHarness.create();
    keyStore = MemorySecureKeyStore();
    shareSource = ControllableIngestionSource(
      sourceId: 'android_share',
      displayName: 'Android Share Intent (WhatsApp / gallery apps)',
    );
    visionCallCount = 0;
    await rebuildServices();
    await keys.addKey(
      label: 'Primary',
      apiKey: 'gsk_test_primary_phase10_hhhh',
    );
  });

  tearDown(() async {
    await shareSource.dispose();
    await harness.dispose();
  });

  Future<File> makeImage(String name) async {
    final file = File('${harness.paths.imagesDirectoryPath}/$name');
    await file.writeAsBytes(
      List<int>.generate(64, (i) => (i + name.hashCode) & 0xff),
    );
    return file;
  }

  Future<BatchItemReviewOutcome?> acceptKeepSeparate(
    ImportQueueItemRecord item,
    VisionJobResult? vision,
    List<DuplicateMatch> duplicates,
  ) async {
    final extraction =
        vision?.extraction ??
        const ReceiptExtraction(bankName: 'HBL', amount: 1, currency: 'PKR');
    return BatchItemReviewOutcome(
      extraction: extraction,
      adminMessage: item.adminNoteOverride ?? extraction.adminMessage,
      duplicateDecision: DuplicateDecision.keepSeparate,
      duplicateOfReceiptId: duplicates.isEmpty
          ? null
          : duplicates.first.existing.id,
    );
  }

  Future<void> importCount(
    int count, {
    required String prefix,
    DateTime? accountingDate,
  }) async {
    final files = <IngestedFile>[];
    for (var i = 0; i < count; i++) {
      final image = await makeImage('${prefix}_$i.jpg');
      files.add(IngestedFile(path: image.path, sourceKind: 'whatsapp_share'));
    }
    final batch = await batchService.enqueueFiles(
      accountingDate: accountingDate ?? day,
      source: 'whatsapp_share',
      files: files,
    );
    await batchService.processQueued(
      batchId: batch.id,
      onNeedsReview: acceptKeepSeparate,
    );
  }

  test(
    'Phase 10 end-to-end production readiness path (mocked Groq)',
    () async {
      // --- 1–8: WhatsApp share → mocked Groq → classify → save ---
      final customer = await customers.create(name: 'Ali Khan');
      await customers.addAlias(
        customerId: customer.id,
        aliasName: 'Ali',
        approvalStatus: AliasApprovalStatus.approved,
      );
      final dealer = await dealers.create(name: 'Hub Filling Station');
      await dealers.addAlias(
        dealerId: dealer.id,
        aliasName: 'Hub',
        approvalStatus: AliasApprovalStatus.approved,
      );

      final accounts = await offices.listSelectableForNewEntries();
      final accountAliases = <String, List<OfficeAccountAliasRecord>>{};
      for (final account in accounts) {
        accountAliases[account.id] = await offices.listAliases(account.id);
      }

      final shareImage = await makeImage('wa_single.jpg');
      shareSource.setInitial([
        IngestedFile(
          path: shareImage.path,
          sourceKind: 'android_share',
          mimeType: 'image/jpeg',
          displayName: 'IMG_WA.jpg',
        ),
      ]);
      expect(await shareSource.isAvailable, isTrue);
      final shared = await shareSource.getInitialFiles();
      expect(shared, hasLength(1));

      late ClassificationResult classified;
      final singleBatch = await batchService.enqueueFiles(
        accountingDate: day,
        source: 'android_share',
        files: shared,
      );
      await batchService.processQueued(
        batchId: singleBatch.id,
        onNeedsReview: (item, vision, duplicates) async {
          expect(vision?.extraction, isNotNull);
          final extraction = vision!.extraction!;
          expect(extraction.adminMessage, contains('Mutalib'));
          expect(extraction.receiverBankAccountName, contains('Azlan'));

          classified = BusinessClassificationService().classify(
            input: ClassificationInput(
              bankSenderName: extraction.senderBankAccountName,
              bankReceiverName: extraction.receiverBankAccountName,
              adminMessage: extraction.adminMessage,
              bankDirectionHint: DbReceiptType.received,
            ),
            accounts: accounts,
            accountAliases: accountAliases,
            customers: [customer],
            customerAliases: {
              customer.id: await customers.listAliases(customer.id),
            },
            dealers: [dealer],
            dealerAliases: {dealer.id: await dealers.listAliases(dealer.id)},
          );
          expect(classified.officeAccountId, DefaultOfficeAccountIds.mutalib);
          expect(classified.customerId, customer.id);
          expect(classified.proposedReceiptType, DbReceiptType.received);

          return BatchItemReviewOutcome(
            extraction: extraction,
            adminMessage: extraction.adminMessage,
            mappedAccountId: classified.officeAccountId,
            customerId: classified.customerId,
            receiptType: classified.proposedReceiptType,
            reviewStatus: DbReviewStatus.pendingReview,
          );
        },
      );

      var rows = await receipts.listByAccountingDate(day);
      expect(rows, hasLength(1));
      final saved = rows.single;
      expect(saved.mappedAccountId, DefaultOfficeAccountIds.mutalib);
      expect(saved.customerId, customer.id);
      expect(saved.entryStatus, DbEntryStatus.pending);

      // Isolate the 20+5 scenario on a clean day count.
      await receipts.softDelete(id: saved.id, changedBy: 'phase10');

      // --- 9–10: import 20, mark 12 Entered ---
      await importCount(20, prefix: 'batch20');
      rows = await receipts.listByAccountingDate(day);
      expect(rows, hasLength(20));
      rows.sort(
        (a, b) => (a.transactionId ?? a.id).compareTo(b.transactionId ?? b.id),
      );
      final enteredIds = <String>[];
      for (var i = 0; i < 12; i++) {
        final marked = await entry.markEntered(
          id: rows[i].id,
          enteredBy: 'clerk',
        );
        enteredIds.add(marked.id);
        expect(marked.entryStatus, DbEntryStatus.entered);
        expect(marked.enteredAt, isNotNull);
      }

      // --- 11–12: restart; ticks remain ---
      await harness.reopen();
      await rebuildServices();
      rows = await receipts.listByAccountingDate(day);
      expect(rows, hasLength(20));
      final stillEntered = rows
          .where((r) => r.entryStatus == DbEntryStatus.entered)
          .toList();
      expect(stillEntered, hasLength(12));
      for (final id in enteredIds) {
        expect(stillEntered.any((r) => r.id == id), isTrue);
      }

      // --- 13–14: +5 → 25 total, 12 entered, 13 pending ---
      await importCount(5, prefix: 'batch5');
      rows = await receipts.listByAccountingDate(day);
      expect(rows, hasLength(25));
      expect(
        rows.where((r) => r.entryStatus == DbEntryStatus.entered).length,
        12,
      );
      expect(
        rows.where((r) => r.entryStatus == DbEntryStatus.pending).length,
        13,
      );

      // --- 15: late receipt yesterday ---
      await importCount(1, prefix: 'late', accountingDate: yesterday);
      expect(await receipts.countByAccountingDate(yesterday), 1);

      // --- 16: duplicate detection ---
      final existing = rows.first;
      final dupes = await receipts.findPossibleDuplicates(
        ReceiptImportDraft(
          transactionId: existing.transactionId,
          bankName: existing.bankName,
          amount: existing.amount,
          imageHash: existing.imageHash,
        ),
        accountingDate: day,
      );
      expect(dupes, isNotEmpty);
      expect(dupes.first.existing.id, existing.id);

      // --- 17: edit Pending ---
      final pending = rows.firstWhere(
        (r) => r.entryStatus == DbEntryStatus.pending,
      );
      final pendingEdited = await receipts.updateReceipt(
        updated: pending.copyWith(
          adminMessage: 'Customer Ali Mutalib (corrected note)',
          notes: 'Pending desk edit',
        ),
        changedBy: 'clerk',
        reason: 'Pending review edit',
      );
      expect(pendingEdited.entryStatus, DbEntryStatus.pending);
      expect(pendingEdited.adminMessage, contains('corrected note'));

      // --- 18–21: Entered amount edit → mandatory recon ---
      final entered = stillEntered.first;
      expect(
        () => entry.applyFinancialEdit(
          id: entered.id,
          newAmount: entered.amount / 10,
          changedBy: 'clerk',
        ),
        throwsStateError,
      );

      final diffs = FinancialChangeDetector.detect(
        entered,
        ReceiptFinancialPatch(amount: entered.amount / 10),
      );
      expect(diffs, isNotEmpty);
      expect(diffs.any((d) => d.field == 'amount'), isTrue);
      expect(diffs.first.oldValue, isNot(diffs.first.newValue));

      final corrected = await entry.applyFinancialEdit(
        id: entered.id,
        newAmount: entered.amount / 10,
        changedBy: 'clerk',
        userConfirmedReconciliation: true,
      );
      expect(corrected.entryStatus, DbEntryStatus.entered);
      expect(corrected.reviewStatus, DbReviewStatus.needsReconciliation);
      expect(corrected.priorAmount, entered.amount);
      expect(corrected.amount, entered.amount / 10);
      expect(corrected.enteredAt, entered.enteredAt);

      // --- 22–23: WinForms correction completed ---
      final completed = await entry.confirmReconciliationReviewed(
        id: corrected.id,
        reviewedBy: 'clerk',
        correctionNotes: 'Corrected manually in WinForms',
      );
      expect(completed.reviewStatus, DbReviewStatus.approved);
      expect(completed.entryStatus, DbEntryStatus.entered);
      expect(completed.reconciliationCompletedAt, isNotNull);

      // --- 24: audit history ---
      final audits = await receipts.listAuditHistory(corrected.id);
      expect(audits, isNotEmpty);
      expect(audits.any((a) => a.fieldName == 'amount'), isTrue);
      final cases = await entry.listCasesForReceipt(corrected.id);
      expect(cases, isNotEmpty);
      expect(cases.first.previousAmount, entered.amount);
      expect(cases.first.correctedAmount, entered.amount / 10);
      expect(cases.first.correctionNotes, 'Corrected manually in WinForms');

      // --- 25: delete + restore historical ---
      final historical = (await receipts.listByAccountingDate(
        yesterday,
      )).single;
      await receipts.softDelete(id: historical.id, changedBy: 'clerk');
      expect(await receipts.countByAccountingDate(yesterday), 0);
      await receipts.restore(id: historical.id, changedBy: 'clerk');
      expect(await receipts.countByAccountingDate(yesterday), 1);

      // --- 26–27: PDF + XLSX ---
      final query = ReportQueryService(
        receipts: receipts,
        offices: offices,
        customers: customers,
        dealers: dealers,
      );
      final export = ReportExportService(query: query, paths: harness.paths);
      final pdf = await export.exportToFile(
        criteria: ReportCriteria(
          kind: ReportKind.dailyReceipt,
          accountingDate: day,
        ),
        format: ReportFormat.pdf,
      );
      final xlsx = await export.exportToFile(
        criteria: ReportCriteria(
          kind: ReportKind.dailyReceipt,
          accountingDate: day,
        ),
        format: ReportFormat.xlsx,
      );
      expect(File(pdf.filePath).existsSync(), isTrue);
      expect(pdf.bytesWritten, greaterThan(100));
      expect(File(xlsx.filePath).existsSync(), isTrue);
      expect(xlsx.bytesWritten, greaterThan(100));
      expect(pdf.document.summary.rowCount, 25);

      final beforeBackup = await receipts.listByAccountingDate(day);
      final statusSnapshot = {
        for (final r in beforeBackup)
          r.id: (r.entryStatus, r.reviewStatus, r.amount),
      };

      // --- 28–30: backup + restore + statuses ---
      var backup = BackupService(
        paths: harness.paths,
        database: harness.database,
        crypto: BackupCrypto(iterations: 1000),
      );
      final backed = await backup.createFullBackup();
      expect(backed.verified, isTrue);

      await harness.reopen();
      await rebuildServices();
      backup = BackupService(
        paths: harness.paths,
        database: harness.database,
        crypto: BackupCrypto(iterations: 1000),
      );
      await receipts.appendImport(
        accountingDate: day,
        source: 'noise',
        drafts: [harness.draft(transactionId: 'NOISE-RESTORE')],
      );
      final restored = await backup.restoreFromArchive(
        archivePath: backed.archivePath,
        confirmReplace: true,
      );
      expect(restored.restored, isTrue);
      expect(restored.verifiedCounts, isTrue);

      await harness.reopen();
      await rebuildServices();
      final afterRestore = await receipts.listByAccountingDate(day);
      expect(afterRestore, hasLength(25));
      for (final r in afterRestore) {
        final snap = statusSnapshot[r.id];
        expect(snap, isNotNull, reason: 'UUID ${r.id} missing after restore');
        expect(r.entryStatus, snap!.$1);
        expect(r.reviewStatus, snap.$2);
        expect(r.amount, snap.$3);
      }
      expect(
        afterRestore
            .where((r) => r.entryStatus == DbEntryStatus.entered)
            .length,
        12,
      );

      // --- 31: offline — image preserved, vision fails ---
      var offline = true;
      await rebuildServices(offline: () => offline);
      final offlineImage = await makeImage('offline.jpg');
      final offlineBatch = await batchService.enqueueFiles(
        accountingDate: day,
        source: 'gallery',
        files: [IngestedFile(path: offlineImage.path, sourceKind: 'gallery')],
      );
      await batchService.processQueued(
        batchId: offlineBatch.id,
        onNeedsReview: acceptKeepSeparate,
      );
      expect(File(offlineImage.path).existsSync(), isTrue);
      offline = false;

      // --- 32: Groq auth error (mocked) ---
      final badClient = GroqVisionClient(
        httpClient: MockClient(
          (request) async =>
              http.Response('{"error":{"message":"Invalid API Key"}}', 401),
        ),
      );
      final listed = await keys.list();
      expect(listed, isNotEmpty);
      final secret = await keyStore.read(listed.first.secureKeySlot!);
      await expectLater(
        badClient.extractReceipt(
          apiKey: secret ?? '',
          endpoint: GroqConstants.defaultEndpoint,
          model: GroqConstants.defaultVisionModel,
          imageBytes: Uint8List.fromList(await offlineImage.readAsBytes()),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<GroqFailure>()),
      );

      // --- 33: API key replacement in secure storage ---
      const replacement = 'gsk_test_replaced_phase10_hhhhhhhh';
      await keyStore.write(listed.first.secureKeySlot!, replacement);
      await configs.update(
        listed.first.copyWith(maskedKeyHint: maskApiKey(replacement)),
      );
      expect(await keyStore.read(listed.first.secureKeySlot!), replacement);

      // --- 34: Android share intent stream ---
      final shareAgain = await makeImage('share2.jpg');
      final liveFuture = shareSource.watchIncomingFiles().first;
      shareSource.emit([
        IngestedFile(
          path: shareAgain.path,
          sourceKind: 'android_share',
          mimeType: 'image/jpeg',
        ),
      ]);
      final live = await liveFuture;
      expect(live.single.sourceKind, 'android_share');

      // --- Migration / schema smoke ---
      expect(DbSchema.version, 6);
      final db = await harness.database.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = {for (final t in tables) t['name'] as String};
      expect(names.contains(DbSchema.receipts), isTrue);
      expect(names.contains(DbSchema.reconciliationCases), isTrue);
      expect(names.contains(DbSchema.importBatches), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('35 light and dark themes build without errors', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.extensions.values, isNotEmpty);
    expect(dark.extensions.values, isNotEmpty);
  });
}
