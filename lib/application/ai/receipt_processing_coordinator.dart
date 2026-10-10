import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/ai/ai_processing_mode.dart';
import 'package:ai_bank_receipt_manager/application/ai/ai_settings_service.dart';
import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/ocr/offline_ocr_engine.dart';
import 'package:ai_bank_receipt_manager/application/ocr/offline_receipt_extractor.dart';
import 'package:ai_bank_receipt_manager/data/ai/gemini_constants.dart';
import 'package:ai_bank_receipt_manager/data/ai/gemini_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Routes receipt processing to exactly one active mode.
/// Never calls multiple cloud providers for the same job.
class ReceiptProcessingCoordinator {
  ReceiptProcessingCoordinator({
    required AiSettingsService settings,
    required GroqApiConfigurationRepository configs,
    required SecureKeyStore keyStore,
    required AiExtractionRepository extractions,
    required String imagesDirectoryPath,
    required OfflineOcrEngine ocrEngine,
    ReceiptVisionService? groqVision,
    GroqVisionClient? groqClient,
    GeminiVisionClient? geminiClient,
    OfflineReceiptExtractor? extractor,
    Uuid? uuid,
  }) : _settings = settings,
       _configs = configs,
       _keys = keyStore,
       _extractions = extractions,
       _imagesDirectoryPath = imagesDirectoryPath,
       _ocr = ocrEngine,
       _groqVision = groqVision,
       _groq = groqClient ?? GroqVisionClient(),
       _gemini = geminiClient ?? GeminiVisionClient(),
       _extractor = extractor ?? OfflineReceiptExtractor(),
       _uuid = uuid ?? const Uuid();

  final AiSettingsService _settings;
  final GroqApiConfigurationRepository _configs;
  final SecureKeyStore _keys;
  final AiExtractionRepository _extractions;
  final String _imagesDirectoryPath;
  final OfflineOcrEngine _ocr;
  final ReceiptVisionService? _groqVision;
  final GroqVisionClient _groq;
  final GeminiVisionClient _gemini;
  final OfflineReceiptExtractor _extractor;
  final Uuid _uuid;

  bool _busy = false;
  AiProviderKind? lastCloudProviderCalled;

  Future<VisionJobResult> processAuthorizedImage({
    required File sourceFile,
    required bool userAuthorizedUpload,
    String? mimeType,
    String? existingReceiptId,
  }) async {
    if (_busy) {
      throw const GroqFailure(
        kind: GroqFailureKind.cancelled,
        message: 'Another receipt is already being processed.',
      );
    }
    _busy = true;
    lastCloudProviderCalled = null;
    try {
      final mode = await _settings.getProcessingMode();
      final bytes = await sourceFile.readAsBytes();
      final hash = sha256HexOfBytes(Uint8List.fromList(bytes));
      final storedPath = await _persistImage(sourceFile, bytes);
      final mediaType = mimeType ?? _guessMime(sourceFile.path);

      if (mode == AiProcessingMode.manual) {
        final draft = await _extractions.create(
          receiptId: existingReceiptId,
          imagePath: storedPath,
          imageHash: hash,
          processingStatus: AiProcessingStatus.needsReview,
          authorizationGranted: userAuthorizedUpload,
        );
        return VisionJobResult.failed(
          extractionRecord: draft,
          failure: const GroqFailure(
            kind: GroqFailureKind.cancelled,
            message: 'Manual Entry mode — enter fields without AI/OCR.',
          ),
          imagePath: storedPath,
          imageHash: hash,
        );
      }

      if (mode == AiProcessingMode.offlineOcr) {
        return _runOfflineOcr(
          bytes: Uint8List.fromList(bytes),
          mimeType: mediaType,
          storedPath: storedPath,
          hash: hash,
          existingReceiptId: existingReceiptId,
          authorized: userAuthorizedUpload,
        );
      }

      if (!userAuthorizedUpload) {
        throw const GroqFailure(
          kind: GroqFailureKind.unauthorizedUpload,
          message: 'Upload was not authorized by the user.',
        );
      }

      try {
        return await _runCloud(
          mode: mode,
          bytes: Uint8List.fromList(bytes),
          mimeType: mediaType,
          storedPath: storedPath,
          hash: hash,
          existingReceiptId: existingReceiptId,
        );
      } on GroqFailure catch (failure) {
        final fallback = await _settings.getOfflineFallbackEnabled();
        if (fallback && _shouldFallbackToOcr(failure)) {
          return _runOfflineOcr(
            bytes: Uint8List.fromList(bytes),
            mimeType: mediaType,
            storedPath: storedPath,
            hash: hash,
            existingReceiptId: existingReceiptId,
            authorized: userAuthorizedUpload,
            priorFailure: failure,
          );
        }
        final draft = await _extractions.create(
          receiptId: existingReceiptId,
          imagePath: storedPath,
          imageHash: hash,
          processingStatus: AiProcessingStatus.failed,
          authorizationGranted: userAuthorizedUpload,
        );
        final failed = await _extractions.update(
          AiExtractionRecord(
            id: draft.id,
            receiptId: existingReceiptId,
            imagePath: storedPath,
            imageHash: hash,
            processingStatus: AiProcessingStatus.failed,
            errorCode: failure.kind.name,
            errorMessage: failure.message,
            keyConfigId: failure.configId,
            authorizationGranted: userAuthorizedUpload,
            createdAt: draft.createdAt,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        return VisionJobResult.failed(
          extractionRecord: failed,
          failure: failure,
          imagePath: storedPath,
          imageHash: hash,
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<VisionJobResult> _runCloud({
    required AiProcessingMode mode,
    required Uint8List bytes,
    required String mimeType,
    required String storedPath,
    required String hash,
    String? existingReceiptId,
  }) async {
    final kind = switch (mode) {
      AiProcessingMode.groq => AiProviderKind.groq,
      AiProcessingMode.gemini => AiProviderKind.gemini,
      AiProcessingMode.custom => AiProviderKind.custom,
      _ => throw StateError('Not a cloud mode'),
    };
    lastCloudProviderCalled = kind;

    // Exclusive: Groq path may reuse the existing vision service (Groq only).
    if (kind == AiProviderKind.groq && _groqVision != null) {
      final enabled = await _configs.listEnabledForProvider(
        AiProviderKind.groq,
      );
      if (enabled.isEmpty) {
        throw const GroqFailure(
          kind: GroqFailureKind.noEnabledKeys,
          message: 'No enabled Groq API keys are configured.',
        );
      }
      final groqResult = await _groqVision.processAuthorizedImage(
        sourceFile: File(storedPath),
        userAuthorizedUpload: true,
        mimeType: mimeType,
        existingReceiptId: existingReceiptId,
      );
      if (groqResult.isSuccess) {
        return groqResult;
      }
      final failure = groqResult.failure;
      if (failure != null) {
        throw failure;
      }
      throw const GroqFailure(
        kind: GroqFailureKind.unknown,
        message: 'Groq processing failed.',
      );
    }

    final configs = await _configs.listEnabledForProvider(kind);
    if (configs.isEmpty) {
      throw GroqFailure(
        kind: GroqFailureKind.noEnabledKeys,
        message: 'No enabled ${kind.displayLabel} keys are configured.',
      );
    }

    final draft = await _extractions.create(
      receiptId: existingReceiptId,
      imagePath: storedPath,
      imageHash: hash,
      processingStatus: AiProcessingStatus.pending,
      authorizationGranted: true,
    );

    GroqFailure? last;
    for (final config in configs.take(GroqConstants.maxFallbackAttempts)) {
      final secret = await _keys.read(config.secureKeySlot ?? '');
      if (secret == null || secret.isEmpty) {
        last = GroqFailure(
          kind: GroqFailureKind.authentication,
          message: 'Secure key missing for ${config.label}.',
          configId: config.id,
          retryableWithNextKey: true,
        );
        continue;
      }
      try {
        final ExtractionParseResult parsed;
        final modelUsed =
            config.modelHint ??
            (kind == AiProviderKind.gemini
                ? GeminiConstants.defaultVisionModel
                : GroqConstants.defaultVisionModel);
        if (kind == AiProviderKind.gemini) {
          parsed = await _gemini.extractReceipt(
            apiKey: secret,
            endpoint: config.endpoint.isEmpty
                ? GeminiConstants.defaultEndpoint
                : config.endpoint,
            model: modelUsed,
            imageBytes: bytes,
            mimeType: mimeType,
            configId: config.id,
            maxOutputTokens: config.maxCompletionTokens,
          );
        } else {
          parsed = await _groq.extractReceipt(
            apiKey: secret,
            endpoint: config.endpoint,
            model: modelUsed,
            imageBytes: bytes,
            mimeType: mimeType,
            configId: config.id,
            maxCompletionTokensOverride: config.maxCompletionTokens,
          );
        }
        final updated = await _extractions.update(
          AiExtractionRecord(
            id: draft.id,
            receiptId: existingReceiptId,
            imagePath: storedPath,
            imageHash: hash,
            rawAiJson: parsed.rawJson,
            rawParseStatus: parsed.status.name,
            processingStatus: existingReceiptId != null
                ? AiProcessingStatus.proposed
                : AiProcessingStatus.needsReview,
            modelUsed: modelUsed,
            keyConfigId: config.id,
            authorizationGranted: true,
            createdAt: draft.createdAt,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        await _configs.recordTestSuccess(config.id);
        return VisionJobResult.success(
          extractionRecord: updated,
          extraction: parsed.extraction!,
          imagePath: storedPath,
          imageHash: hash,
        );
      } on GroqFailure catch (failure) {
        last = failure;
        await _configs.recordError(id: config.id, status: failure.kind.name);
        if (failure.kind == GroqFailureKind.outputTokenLimit ||
            !failure.retryableWithNextKey) {
          break;
        }
      }
    }
    throw last ??
        const GroqFailure(
          kind: GroqFailureKind.unknown,
          message: 'Cloud AI processing failed.',
        );
  }

  Future<VisionJobResult> _runOfflineOcr({
    required Uint8List bytes,
    required String mimeType,
    required String storedPath,
    required String hash,
    required bool authorized,
    String? existingReceiptId,
    GroqFailure? priorFailure,
  }) async {
    final draft = await _extractions.create(
      receiptId: existingReceiptId,
      imagePath: storedPath,
      imageHash: hash,
      processingStatus: AiProcessingStatus.pending,
      authorizationGranted: authorized,
    );
    try {
      final ocr = await _ocr.recognize(bytes, mimeType: mimeType);
      final extraction = _extractor.extract(ocr);
      final note = priorFailure == null
          ? extraction.modelNotes
          : '${extraction.modelNotes ?? ''} '
                'Cloud AI unavailable (${priorFailure.kind.name}); '
                'used Offline OCR.';
      final updated = await _extractions.update(
        AiExtractionRecord(
          id: draft.id,
          receiptId: existingReceiptId,
          imagePath: storedPath,
          imageHash: hash,
          rawAiJson: extraction.toJsonString(),
          rawParseStatus: ExtractionParseStatus.ok.name,
          processingStatus: AiProcessingStatus.needsReview,
          modelUsed: ocr.engineName,
          authorizationGranted: authorized,
          errorCode: priorFailure?.kind.name,
          errorMessage: priorFailure?.message,
          createdAt: draft.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return VisionJobResult.success(
        extractionRecord: updated,
        extraction: ReceiptExtraction(
          bankName: extraction.bankName,
          senderBankAccountName: extraction.senderBankAccountName,
          receiverBankAccountName: extraction.receiverBankAccountName,
          amount: extraction.amount,
          currency: extraction.currency,
          transactionReference: extraction.transactionReference,
          transactionDateTimeRaw: extraction.transactionDateTimeRaw,
          whatsappSender: extraction.whatsappSender,
          adminMessage: extraction.adminMessage,
          suggestedCustomerName: extraction.suggestedCustomerName,
          suggestedDealerName: extraction.suggestedDealerName,
          suggestedOfficeAccountName: extraction.suggestedOfficeAccountName,
          bankDirectionHint: extraction.bankDirectionHint,
          maskedAccountNumbers: extraction.maskedAccountNumbers,
          uncertainFields: extraction.uncertainFields,
          missingFields: extraction.missingFields,
          fieldConfidence: extraction.fieldConfidence,
          overallConfidence: extraction.overallConfidence,
          modelNotes: note?.trim(),
        ),
        imagePath: storedPath,
        imageHash: hash,
      );
    } catch (error) {
      final failed = await _extractions.update(
        AiExtractionRecord(
          id: draft.id,
          receiptId: existingReceiptId,
          imagePath: storedPath,
          imageHash: hash,
          processingStatus: AiProcessingStatus.failed,
          errorCode: 'offline_ocr',
          errorMessage: sanitizeProviderMessage('$error'),
          authorizationGranted: authorized,
          createdAt: draft.createdAt,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      return VisionJobResult.failed(
        extractionRecord: failed,
        failure: GroqFailure(
          kind: GroqFailureKind.unknown,
          message: 'Offline OCR failed. Enter details manually.',
        ),
        imagePath: storedPath,
        imageHash: hash,
      );
    }
  }

  bool _shouldFallbackToOcr(GroqFailure failure) {
    return switch (failure.kind) {
      GroqFailureKind.rateLimit ||
      GroqFailureKind.outputTokenLimit ||
      GroqFailureKind.network ||
      GroqFailureKind.timeout ||
      GroqFailureKind.server ||
      GroqFailureKind.authentication ||
      GroqFailureKind.modelUnavailable ||
      GroqFailureKind.malformedResponse ||
      GroqFailureKind.schemaInvalid ||
      GroqFailureKind.noEnabledKeys => true,
      _ => false,
    };
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
}
