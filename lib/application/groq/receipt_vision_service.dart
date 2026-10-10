import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/groq/groq_key_manager.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ReceiptVisionService {
  ReceiptVisionService({
    required GroqKeyManager keyManager,
    required GroqApiConfigurationRepository configs,
    required AiExtractionRepository extractions,
    required ReceiptRepository receipts,
    required String imagesDirectoryPath,
    GroqVisionClient? client,
    Uuid? uuid,
  }) : _keys = keyManager,
       _configs = configs,
       _extractions = extractions,
       _receipts = receipts,
       _imagesDirectoryPath = imagesDirectoryPath,
       _client = client ?? GroqVisionClient(),
       _uuid = uuid ?? const Uuid();

  final GroqKeyManager _keys;
  final GroqApiConfigurationRepository _configs;
  final AiExtractionRepository _extractions;
  final ReceiptRepository _receipts;
  final String _imagesDirectoryPath;
  final GroqVisionClient _client;
  final Uuid _uuid;

  /// Persists the screenshot locally, then runs bounded key fallback extraction.
  Future<VisionJobResult> processAuthorizedImage({
    required File sourceFile,
    required bool userAuthorizedUpload,
    String? mimeType,
    String? existingReceiptId,
  }) async {
    if (!userAuthorizedUpload) {
      throw const GroqFailure(
        kind: GroqFailureKind.unauthorizedUpload,
        message: 'Upload was not authorized by the user.',
      );
    }

    final bytes = await sourceFile.readAsBytes();
    final hash = sha256HexOfBytes(Uint8List.fromList(bytes));
    final storedPath = await _persistImage(sourceFile, bytes);
    final mediaType = mimeType ?? _guessMime(sourceFile.path);

    final draft = await _extractions.create(
      receiptId: existingReceiptId,
      imagePath: storedPath,
      imageHash: hash,
      processingStatus: AiProcessingStatus.pending,
      authorizationGranted: true,
    );

    try {
      final success = await _extractWithFallback(
        imageBytes: Uint8List.fromList(bytes),
        mimeType: mediaType,
      );
      final updated = await _extractions.update(
        AiExtractionRecord(
          id: draft.id,
          receiptId: existingReceiptId,
          imagePath: storedPath,
          imageHash: hash,
          rawAiJson: success.parse.rawJson,
          rawParseStatus: success.parse.status.name,
          processingStatus: existingReceiptId != null
              ? AiProcessingStatus.proposed
              : AiProcessingStatus.needsReview,
          modelUsed: success.model,
          keyConfigId: success.configId,
          proposedJson: existingReceiptId != null
              ? success.parse.extraction!.toJsonString()
              : null,
          authorizationGranted: true,
          createdAt: draft.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return VisionJobResult.success(
        extractionRecord: updated,
        extraction: success.parse.extraction!,
        imagePath: storedPath,
        imageHash: hash,
      );
    } on GroqFailure catch (failure) {
      final updated = await _extractions.update(
        AiExtractionRecord(
          id: draft.id,
          receiptId: existingReceiptId,
          imagePath: storedPath,
          imageHash: hash,
          processingStatus: AiProcessingStatus.failed,
          errorCode: failure.kind.name,
          errorMessage: failure.message,
          keyConfigId: failure.configId,
          authorizationGranted: true,
          createdAt: draft.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return VisionJobResult.failed(
        extractionRecord: updated,
        failure: failure,
        imagePath: storedPath,
        imageHash: hash,
      );
    }
  }

  /// Reprocesses an Entered receipt. Never overwrites saved financial fields.
  Future<VisionJobResult> reprocessEnteredReceipt({
    required String receiptId,
    required bool userAuthorizedUpload,
  }) async {
    final receipt = await _receipts.getById(receiptId);
    if (receipt == null) {
      throw StateError('Receipt $receiptId was not found.');
    }
    if (receipt.entryStatus != DbEntryStatus.entered) {
      throw StateError('Only Entered receipts use proposed-change reprocess.');
    }
    final imagePath = receipt.originalImagePath;
    if (imagePath == null || imagePath.isEmpty) {
      throw StateError('Entered receipt has no preserved image to reprocess.');
    }
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw StateError('Preserved receipt image is missing on disk.');
    }

    final result = await processAuthorizedImage(
      sourceFile: file,
      userAuthorizedUpload: userAuthorizedUpload,
      existingReceiptId: receiptId,
    );

    // Explicitly keep Entered financial fields and tick untouched.
    final still = await _receipts.getById(receiptId);
    if (still == null ||
        still.entryStatus != DbEntryStatus.entered ||
        still.amount != receipt.amount ||
        still.bankName != receipt.bankName ||
        still.transactionId != receipt.transactionId ||
        still.currency != receipt.currency) {
      throw StateError('Reprocess must not alter Entered financial fields.');
    }

    if (result.isSuccess) {
      // Never overwrite Entered financial fields or reset reconciliation status.
      await _receipts.updateReceipt(
        updated: receipt.copyWith(
          entryStatus: receipt.entryStatus,
          enteredAt: receipt.enteredAt,
          enteredBy: receipt.enteredBy,
          amount: receipt.amount,
          accountingDate: receipt.accountingDate,
          receiptType: receipt.receiptType,
          mappedAccountId: receipt.mappedAccountId,
          customerId: receipt.customerId,
          dealerId: receipt.dealerId,
          transactionId: receipt.transactionId,
          reviewStatus: receipt.reviewStatus,
          priorAmount: receipt.priorAmount,
          priorPartyName: receipt.priorPartyName,
          priorAccountId: receipt.priorAccountId,
          reconciliationCompletedAt: receipt.reconciliationCompletedAt,
          notes: _appendNote(
            receipt.notes,
            'AI reprocess proposed changes for review (extraction ${result.extractionRecord.id}).',
          ),
        ),
        reason:
            'AI reprocess proposed review only; financial fields unchanged.',
      );
    }
    return result;
  }

  /// Saves user-corrected fields as a new pending receipt. Raw AI stays separate.
  Future<ReceiptRecord> saveCorrectedImport({
    required AiExtractionRecord extractionRecord,
    required ReceiptExtraction corrected,
    required DateTime accountingDate,
    String source = 'groq_vision',
    String? existingBatchId,
    String? mappedAccountId,
    String? customerId,
    String? dealerId,
    DbReceiptType receiptType = DbReceiptType.unknown,
    DbReviewStatus reviewStatus = DbReviewStatus.pendingReview,
  }) async {
    if (extractionRecord.receiptId != null) {
      throw StateError(
        'Use applyProposedReview for reprocessed Entered receipts.',
      );
    }

    final receiptId = _uuid.v4();
    final draft = ReceiptImportDraft(
      id: receiptId,
      transactionId: corrected.transactionReference,
      bankName: corrected.bankName?.trim().isNotEmpty == true
          ? corrected.bankName!.trim()
          : 'Unknown bank',
      bankSenderName: corrected.senderBankAccountName,
      bankReceiverName: corrected.receiverBankAccountName,
      amount: corrected.amount ?? 0,
      currency: corrected.currency?.trim().isNotEmpty == true
          ? corrected.currency!.trim()
          : 'PKR',
      transactionDateTime: _tryParseDate(corrected.transactionDateTimeRaw),
      whatsappSender: corrected.whatsappSender,
      adminMessage: corrected.adminMessage,
      originalImagePath: extractionRecord.imagePath,
      imageHash: extractionRecord.imageHash,
      confidenceScore: corrected.overallConfidence,
      reviewStatus: reviewStatus,
      notes: corrected.modelNotes,
      receiptType: receiptType,
      mappedAccountId: mappedAccountId,
      customerId: customerId,
      dealerId: dealerId,
    );

    await _receipts.appendImport(
      accountingDate: accountingDate,
      drafts: [draft],
      source: source,
      notes: 'Saved after user review of AI extraction.',
      existingBatchId: existingBatchId,
    );

    final created = await _receipts.getById(receiptId);
    if (created == null) {
      throw StateError('Receipt was not created after import.');
    }

    await _extractions.update(
      AiExtractionRecord(
        id: extractionRecord.id,
        receiptId: created.id,
        imagePath: extractionRecord.imagePath,
        imageHash: extractionRecord.imageHash,
        rawAiJson: extractionRecord.rawAiJson,
        rawParseStatus: extractionRecord.rawParseStatus,
        processingStatus: AiProcessingStatus.succeeded,
        errorCode: extractionRecord.errorCode,
        errorMessage: extractionRecord.errorMessage,
        modelUsed: extractionRecord.modelUsed,
        keyConfigId: extractionRecord.keyConfigId,
        proposedJson: extractionRecord.proposedJson,
        userCorrectedJson: corrected.toJsonString(),
        appliedToReceipt: true,
        authorizationGranted: extractionRecord.authorizationGranted,
        createdAt: extractionRecord.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    return created;
  }

  /// Manual entry when AI failed but the image was preserved.
  Future<ReceiptRecord> saveManualAfterFailure({
    required AiExtractionRecord extractionRecord,
    required ReceiptExtraction manual,
    required DateTime accountingDate,
    String? existingBatchId,
    String? mappedAccountId,
    String? customerId,
    String? dealerId,
    DbReceiptType receiptType = DbReceiptType.unknown,
    DbReviewStatus reviewStatus = DbReviewStatus.pendingReview,
  }) {
    return saveCorrectedImport(
      extractionRecord: extractionRecord,
      corrected: manual,
      accountingDate: accountingDate,
      source: 'manual_after_ai_failure',
      existingBatchId: existingBatchId,
      mappedAccountId: mappedAccountId,
      customerId: customerId,
      dealerId: dealerId,
      receiptType: receiptType,
      reviewStatus: reviewStatus,
    );
  }

  Future<_ExtractSuccess> _extractWithFallback({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final configs = await _configs.listEnabledForFallback();
    if (configs.isEmpty) {
      throw const GroqFailure(
        kind: GroqFailureKind.noEnabledKeys,
        message: 'No enabled Groq API keys are configured.',
      );
    }

    final attempts = configs.take(GroqConstants.maxFallbackAttempts).toList();
    GroqFailure? lastFailure;

    for (final config in attempts) {
      final resolved = await _keys.resolveSecret(config);
      if (resolved == null) {
        lastFailure = GroqFailure(
          kind: GroqFailureKind.authentication,
          message: 'Secure key missing for ${config.label}.',
          retryableWithNextKey: true,
          configId: config.id,
        );
        await _configs.recordError(
          id: config.id,
          status: lastFailure.kind.name,
        );
        continue;
      }

      try {
        final parsed = await _client.extractReceipt(
          apiKey: resolved.apiKey,
          endpoint: config.endpoint,
          model: config.modelHint ?? GroqConstants.defaultVisionModel,
          imageBytes: imageBytes,
          mimeType: mimeType,
          configId: config.id,
        );
        await _configs.recordTestSuccess(config.id);
        return _ExtractSuccess(
          parse: parsed,
          configId: config.id,
          model: config.modelHint ?? GroqConstants.defaultVisionModel,
        );
      } on GroqFailure catch (failure) {
        lastFailure = failure;
        await _configs.recordError(id: config.id, status: failure.kind.name);
        if (!failure.retryableWithNextKey) {
          rethrow;
        }
      }
    }

    throw lastFailure ??
        const GroqFailure(
          kind: GroqFailureKind.unknown,
          message: 'All configured Groq keys failed.',
        );
  }

  Future<String> _persistImage(File source, List<int> bytes) async {
    final dir = Directory(_imagesDirectoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final ext = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final target = File(p.join(_imagesDirectoryPath, '${_uuid.v4()}$ext'));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  static String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  static DateTime? _tryParseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.trim());
  }

  static String _appendNote(String? existing, String addition) {
    if (existing == null || existing.trim().isEmpty) {
      return addition;
    }
    return '$existing\n$addition';
  }
}

class _ExtractSuccess {
  const _ExtractSuccess({
    required this.parse,
    required this.configId,
    required this.model,
  });

  final ExtractionParseResult parse;
  final String configId;
  final String model;
}

class VisionJobResult {
  const VisionJobResult._({
    required this.extractionRecord,
    required this.imagePath,
    required this.imageHash,
    this.extraction,
    this.failure,
  });

  factory VisionJobResult.success({
    required AiExtractionRecord extractionRecord,
    required ReceiptExtraction extraction,
    required String imagePath,
    required String imageHash,
  }) {
    return VisionJobResult._(
      extractionRecord: extractionRecord,
      extraction: extraction,
      imagePath: imagePath,
      imageHash: imageHash,
    );
  }

  factory VisionJobResult.failed({
    required AiExtractionRecord extractionRecord,
    required GroqFailure failure,
    required String imagePath,
    required String imageHash,
  }) {
    return VisionJobResult._(
      extractionRecord: extractionRecord,
      failure: failure,
      imagePath: imagePath,
      imageHash: imageHash,
    );
  }

  final AiExtractionRecord extractionRecord;
  final ReceiptExtraction? extraction;
  final GroqFailure? failure;
  final String imagePath;
  final String imageHash;

  bool get isSuccess => extraction != null && failure == null;
}
