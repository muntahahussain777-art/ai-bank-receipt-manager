import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/import/receipt_ingestion.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/import_queue_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// How many AI vision jobs may run at once. Keep low to avoid rate limits.
const int kMaxConcurrentVisionJobs = 1;

enum DuplicateDecision { skip, keepSeparate, reviewExisting }

class BatchImportService {
  BatchImportService({
    required ImportQueueRepository queue,
    required ReceiptRepository receipts,
    required ReceiptVisionService vision,
    required String imagesDirectoryPath,
    Uuid? uuid,
    this.maxConcurrent = kMaxConcurrentVisionJobs,
  }) : _queue = queue,
       _receipts = receipts,
       _vision = vision,
       _imagesDirectoryPath = imagesDirectoryPath,
       _uuid = uuid ?? const Uuid();

  final ImportQueueRepository _queue;
  final ReceiptRepository _receipts;
  final ReceiptVisionService _vision;
  final String _imagesDirectoryPath;
  final Uuid _uuid;
  final int maxConcurrent;

  int _inFlight = 0;

  /// Creates a durable batch and stores every file on disk before AI runs.
  Future<ImportBatchRecord> enqueueFiles({
    required DateTime accountingDate,
    required List<IngestedFile> files,
    required String source,
    String? notes,
    String? sharedAdminNote,
    Map<String, String>? groupIdsByPath,
  }) async {
    if (files.isEmpty) {
      throw ArgumentError('At least one file is required.');
    }

    final batch = await _queue.createBatch(
      accountingDate: accountingDate,
      source: source,
      fileCount: files.length,
      notes: notes,
    );

    for (final file in files) {
      final stored = await _persistLocalCopy(File(file.path), file);
      await _queue.enqueue(
        batchId: batch.id,
        sourceKind: file.sourceKind,
        storedPath: stored.path,
        imageHash: stored.hash,
        mimeType: file.mimeType ?? stored.mimeType,
        displayName: file.displayName ?? p.basename(file.path),
        originalUri: file.originalUri,
        adminNoteOverride: sharedAdminNote,
        groupId: groupIdsByPath?[file.path],
      );
    }

    return _queue.refreshBatchCounts(batch.id);
  }

  Future<void> assignGroup(List<String> itemIds) async {
    await _queue.assignGroup(itemIds: itemIds, groupId: _uuid.v4());
  }

  /// Processes queued items with a bounded concurrency limit.
  ///
  /// Items that need human review are left in [ImportQueueStatus.awaitingReview].
  /// Call [completeItemAfterReview] after the user confirms fields / duplicates.
  Future<List<ImportQueueItemRecord>> processQueued({
    required String batchId,
    required Future<BatchItemReviewOutcome?> Function(
      ImportQueueItemRecord item,
      VisionJobResult? visionResult,
      List<DuplicateMatch> duplicates,
    )
    onNeedsReview,
    bool userAuthorizedUpload = true,
  }) async {
    final items = await _queue.listForBatch(batchId);
    final results = <ImportQueueItemRecord>[];

    // Process one group (or single item) at a time within the concurrency cap.
    final pending = [
      for (final item in items)
        if (item.queueStatus == ImportQueueStatus.queued ||
            item.queueStatus == ImportQueueStatus.failed)
          item,
    ];

    final handledGroups = <String>{};

    for (final item in pending) {
      while (_inFlight >= maxConcurrent) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      final groupId = item.groupId;
      if (groupId != null) {
        if (handledGroups.contains(groupId)) {
          continue;
        }
        handledGroups.add(groupId);
        final groupItems = [
          for (final candidate in pending)
            if (candidate.groupId == groupId) candidate,
        ];
        _inFlight++;
        try {
          results.add(
            await _processGroup(
              primary: item,
              siblings: groupItems,
              userAuthorizedUpload: userAuthorizedUpload,
              onNeedsReview: onNeedsReview,
            ),
          );
        } finally {
          _inFlight--;
        }
      } else {
        _inFlight++;
        try {
          results.add(
            await _processSingle(
              item: item,
              userAuthorizedUpload: userAuthorizedUpload,
              onNeedsReview: onNeedsReview,
            ),
          );
        } finally {
          _inFlight--;
        }
      }
    }

    await _queue.refreshBatchCounts(batchId);
    return results;
  }

  Future<ImportQueueItemRecord> retryItem({
    required String itemId,
    required Future<BatchItemReviewOutcome?> Function(
      ImportQueueItemRecord item,
      VisionJobResult? visionResult,
      List<DuplicateMatch> duplicates,
    )
    onNeedsReview,
    bool userAuthorizedUpload = true,
  }) async {
    final item = await _queue.getItem(itemId);
    if (item == null) {
      throw StateError('Queue item $itemId was not found.');
    }
    final reset = await _queue.updateItem(
      ImportQueueItemRecord(
        id: item.id,
        batchId: item.batchId,
        groupId: item.groupId,
        sourceKind: item.sourceKind,
        originalUri: item.originalUri,
        storedPath: item.storedPath,
        imageHash: item.imageHash,
        mimeType: item.mimeType,
        displayName: item.displayName,
        queueStatus: ImportQueueStatus.queued,
        adminNoteOverride: item.adminNoteOverride,
        retryCount: item.retryCount + 1,
        createdAt: item.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return _processSingle(
      item: reset,
      userAuthorizedUpload: userAuthorizedUpload,
      onNeedsReview: onNeedsReview,
    );
  }

  Future<ImportQueueItemRecord> _processSingle({
    required ImportQueueItemRecord item,
    required bool userAuthorizedUpload,
    required Future<BatchItemReviewOutcome?> Function(
      ImportQueueItemRecord item,
      VisionJobResult? visionResult,
      List<DuplicateMatch> duplicates,
    )
    onNeedsReview,
  }) async {
    var working = await _queue.updateItem(
      _copyItem(item, status: ImportQueueStatus.processing),
    );

    final file = File(working.storedPath);
    if (!file.existsSync()) {
      return _queue.updateItem(
        _copyItem(
          working,
          status: ImportQueueStatus.failed,
          error: 'Original file missing on disk.',
        ),
      );
    }

    VisionJobResult? visionResult;
    final isPdf =
        working.mimeType?.toLowerCase().contains('pdf') == true ||
        working.storedPath.toLowerCase().endsWith('.pdf');

    if (!isPdf) {
      try {
        visionResult = await _vision.processAuthorizedImage(
          sourceFile: file,
          userAuthorizedUpload: userAuthorizedUpload,
          mimeType: working.mimeType,
        );
        // Prefer the durable path already stored for the queue item.
        if (visionResult.imagePath != working.storedPath) {
          // Keep both; queue item retains its preserved path.
        }
      } on GroqFailure catch (failure) {
        working = await _queue.updateItem(
          _copyItem(
            working,
            status: ImportQueueStatus.failed,
            error: failure.message,
          ),
        );
        // Image already preserved on disk — allow manual review path.
        visionResult = null;
      }
    }

    working = await _queue.updateItem(
      _copyItem(
        working,
        status: ImportQueueStatus.awaitingReview,
        extractionId: visionResult?.extractionRecord.id,
      ),
    );

    final draft = _draftFromVision(
      visionResult: visionResult,
      item: working,
    );
    final duplicates = await _receipts.findPossibleDuplicates(
      draft,
      accountingDate: (await _queue.getBatch(working.batchId))!.accountingDate,
    );

    final outcome = await onNeedsReview(working, visionResult, duplicates);
    if (outcome == null) {
      return _queue.updateItem(
        _copyItem(
          working,
          status: ImportQueueStatus.failed,
          error: 'Review cancelled; image preserved for retry.',
        ),
      );
    }

    return _applyOutcome(
      item: working,
      visionResult: visionResult,
      outcome: outcome,
    );
  }

  Future<ImportQueueItemRecord> _processGroup({
    required ImportQueueItemRecord primary,
    required List<ImportQueueItemRecord> siblings,
    required bool userAuthorizedUpload,
    required Future<BatchItemReviewOutcome?> Function(
      ImportQueueItemRecord item,
      VisionJobResult? visionResult,
      List<DuplicateMatch> duplicates,
    )
    onNeedsReview,
  }) async {
    // Multi-image one transaction: process the first image with AI; siblings
    // are attached as notes / kept on disk and marked succeeded with same receipt.
    final primaryResult = await _processSingle(
      item: primary,
      userAuthorizedUpload: userAuthorizedUpload,
      onNeedsReview: onNeedsReview,
    );

    if (primaryResult.receiptId == null) {
      for (final sibling in siblings) {
        if (sibling.id == primary.id) {
          continue;
        }
        await _queue.updateItem(
          _copyItem(
            sibling,
            status: primaryResult.queueStatus,
            error: primaryResult.errorMessage,
          ),
        );
      }
      await _queue.refreshBatchCounts(primary.batchId);
      return primaryResult;
    }

    for (final sibling in siblings) {
      if (sibling.id == primary.id) {
        continue;
      }
      await _queue.updateItem(
        _copyItem(
          sibling,
          status: ImportQueueStatus.succeeded,
          receiptId: primaryResult.receiptId,
        ),
      );
    }
    await _queue.refreshBatchCounts(primary.batchId);
    return primaryResult;
  }

  Future<ImportQueueItemRecord> _applyOutcome({
    required ImportQueueItemRecord item,
    required VisionJobResult? visionResult,
    required BatchItemReviewOutcome outcome,
  }) async {
    final batch = await _queue.getBatch(item.batchId);
    if (batch == null) {
      throw StateError('Batch missing for ${item.batchId}');
    }

    if (outcome.duplicateDecision == DuplicateDecision.skip) {
      return _queue.updateItem(
        _copyItem(
          item,
          status: ImportQueueStatus.skippedDuplicate,
          duplicateOf: outcome.duplicateOfReceiptId,
        ),
      ).then((value) async {
        await _queue.refreshBatchCounts(item.batchId);
        return value;
      });
    }

    final corrected = outcome.extraction;
    final withAdmin = ReceiptExtraction(
      bankName: corrected.bankName,
      senderBankAccountName: corrected.senderBankAccountName,
      receiverBankAccountName: corrected.receiverBankAccountName,
      amount: corrected.amount,
      currency: corrected.currency,
      transactionReference: corrected.transactionReference,
      transactionDateTimeRaw: corrected.transactionDateTimeRaw,
      whatsappSender: corrected.whatsappSender,
      adminMessage: outcome.adminMessage ??
          item.adminNoteOverride ??
          corrected.adminMessage,
      maskedAccountNumbers: corrected.maskedAccountNumbers,
      uncertainFields: corrected.uncertainFields,
      missingFields: corrected.missingFields,
      fieldConfidence: corrected.fieldConfidence,
      overallConfidence: corrected.overallConfidence,
      modelNotes: [
        if (corrected.modelNotes != null) corrected.modelNotes!,
        if (item.groupId != null) 'Grouped multi-image import ${item.groupId}',
        if (outcome.duplicateDecision == DuplicateDecision.keepSeparate)
          'Kept as separate receipt despite possible duplicate.',
      ].join('\n'),
    );

    late final ReceiptRecord receipt;
    if (visionResult != null && visionResult.isSuccess) {
      receipt = await _vision.saveCorrectedImport(
        extractionRecord: visionResult.extractionRecord,
        corrected: withAdmin,
        accountingDate: batch.accountingDate,
        source: item.sourceKind,
        existingBatchId: batch.id,
      );
    } else if (visionResult != null) {
      receipt = await _vision.saveManualAfterFailure(
        extractionRecord: visionResult.extractionRecord,
        manual: withAdmin,
        accountingDate: batch.accountingDate,
        existingBatchId: batch.id,
      );
    } else {
      // PDF / failed before extraction row — append directly, keep image/PDF path.
      final receiptId = _uuid.v4();
      await _receipts.appendImport(
        accountingDate: batch.accountingDate,
        drafts: [
          ReceiptImportDraft(
            id: receiptId,
            transactionId: withAdmin.transactionReference,
            bankName: withAdmin.bankName?.trim().isNotEmpty == true
                ? withAdmin.bankName!.trim()
                : 'Unknown bank',
            bankSenderName: withAdmin.senderBankAccountName,
            bankReceiverName: withAdmin.receiverBankAccountName,
            amount: withAdmin.amount ?? 0,
            currency: withAdmin.currency ?? 'PKR',
            transactionDateTime: DateTime.tryParse(
              withAdmin.transactionDateTimeRaw ?? '',
            ),
            whatsappSender: withAdmin.whatsappSender,
            adminMessage: withAdmin.adminMessage,
            originalImagePath: item.storedPath,
            imageHash: item.imageHash,
            notes: withAdmin.modelNotes,
            receiptType: DbReceiptType.unknown,
          ),
        ],
        source: item.sourceKind,
        notes: 'Batch ${batch.id}',
        existingBatchId: batch.id,
      );
      receipt = (await _receipts.getById(receiptId))!;
    }

    final saved = await _queue.updateItem(
      _copyItem(
        item,
        status: ImportQueueStatus.succeeded,
        receiptId: receipt.id,
        extractionId: visionResult?.extractionRecord.id ?? item.extractionId,
      ),
    );
    await _queue.refreshBatchCounts(item.batchId);
    return saved;
  }

  /// Manual entry without an image (still creates a batch of 1).
  Future<ReceiptRecord> saveManualEntry({
    required DateTime accountingDate,
    required ReceiptExtraction fields,
    String? adminMessage,
  }) async {
    final batch = await _queue.createBatch(
      accountingDate: accountingDate,
      source: 'manual_entry',
      fileCount: 0,
      notes: 'Manual receipt entry',
    );
    final receiptId = _uuid.v4();
    await _receipts.appendImport(
      accountingDate: accountingDate,
      drafts: [
        ReceiptImportDraft(
          id: receiptId,
          transactionId: fields.transactionReference,
          bankName: fields.bankName?.trim().isNotEmpty == true
              ? fields.bankName!.trim()
              : 'Unknown bank',
          bankSenderName: fields.senderBankAccountName,
          bankReceiverName: fields.receiverBankAccountName,
          amount: fields.amount ?? 0,
          currency: fields.currency ?? 'PKR',
          transactionDateTime: DateTime.tryParse(
            fields.transactionDateTimeRaw ?? '',
          ),
          whatsappSender: fields.whatsappSender,
          adminMessage: adminMessage ?? fields.adminMessage,
          notes: fields.modelNotes,
        ),
      ],
      source: 'manual_entry',
      notes: 'Batch ${batch.id}',
      existingBatchId: batch.id,
    );
    await _queue.updateBatch(
      batch.copyWith(
        successCount: 1,
        receiptCount: 1,
        batchStatus: ImportBatchStatus.completed,
      ),
    );
    return (await _receipts.getById(receiptId))!;
  }

  Future<ReceiptRecord> updateAdminNote({
    required String receiptId,
    required String adminMessage,
  }) async {
    final existing = await _receipts.getById(receiptId);
    if (existing == null) {
      throw StateError('Receipt $receiptId was not found.');
    }
    return _receipts.updateReceipt(
      updated: existing.copyWith(adminMessage: adminMessage),
      reason: 'Admin WhatsApp note edited.',
    );
  }

  ReceiptImportDraft _draftFromVision({
    required VisionJobResult? visionResult,
    required ImportQueueItemRecord item,
  }) {
    final extraction = visionResult?.extraction;
    return ReceiptImportDraft(
      transactionId: extraction?.transactionReference,
      bankName: extraction?.bankName ?? 'Unknown bank',
      amount: extraction?.amount ?? 0,
      currency: extraction?.currency ?? 'PKR',
      transactionDateTime: DateTime.tryParse(
        extraction?.transactionDateTimeRaw ?? '',
      ),
      originalImagePath: item.storedPath,
      imageHash: item.imageHash ?? visionResult?.imageHash,
      adminMessage: item.adminNoteOverride ?? extraction?.adminMessage,
      whatsappSender: extraction?.whatsappSender,
    );
  }

  Future<({String path, String hash, String mimeType})> _persistLocalCopy(
    File source,
    IngestedFile meta,
  ) async {
    final bytes = await source.readAsBytes();
    final hash = sha256HexOfBytes(Uint8List.fromList(bytes));
    final dir = Directory(_imagesDirectoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final ext = p.extension(source.path).isEmpty
        ? (meta.isPdf ? '.pdf' : '.jpg')
        : p.extension(source.path);
    final target = File(p.join(_imagesDirectoryPath, '${_uuid.v4()}$ext'));
    await target.writeAsBytes(bytes, flush: true);
    final mime =
        meta.mimeType ??
        (meta.isPdf
            ? 'application/pdf'
            : _guessMime(target.path));
    return (path: target.path, hash: hash, mimeType: mime);
  }

  static String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    return 'image/jpeg';
  }

  ImportQueueItemRecord _copyItem(
    ImportQueueItemRecord item, {
    ImportQueueStatus? status,
    String? error,
    String? extractionId,
    String? receiptId,
    String? duplicateOf,
  }) {
    return ImportQueueItemRecord(
      id: item.id,
      batchId: item.batchId,
      groupId: item.groupId,
      sourceKind: item.sourceKind,
      originalUri: item.originalUri,
      storedPath: item.storedPath,
      imageHash: item.imageHash,
      mimeType: item.mimeType,
      displayName: item.displayName,
      queueStatus: status ?? item.queueStatus,
      errorMessage: error,
      extractionId: extractionId ?? item.extractionId,
      receiptId: receiptId ?? item.receiptId,
      duplicateOfReceiptId: duplicateOf ?? item.duplicateOfReceiptId,
      adminNoteOverride: item.adminNoteOverride,
      retryCount: item.retryCount,
      createdAt: item.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

class BatchItemReviewOutcome {
  const BatchItemReviewOutcome({
    required this.extraction,
    this.adminMessage,
    this.duplicateDecision = DuplicateDecision.keepSeparate,
    this.duplicateOfReceiptId,
  });

  final ReceiptExtraction extraction;
  final String? adminMessage;
  final DuplicateDecision duplicateDecision;
  final String? duplicateOfReceiptId;
}
