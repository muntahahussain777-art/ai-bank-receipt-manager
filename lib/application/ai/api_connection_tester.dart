import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/ai/api_test_result.dart';
import 'package:ai_bank_receipt_manager/data/ai/gemini_constants.dart';
import 'package:ai_bank_receipt_manager/data/ai/gemini_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';

/// Real API tests using synthetic non-financial payloads only.
class ApiConnectionTester {
  ApiConnectionTester({
    required GroqApiConfigurationRepository configs,
    required SecureKeyStore keyStore,
    GroqVisionClient? groqClient,
    GeminiVisionClient? geminiClient,
  }) : _configs = configs,
       _keys = keyStore,
       _groq = groqClient ?? GroqVisionClient(),
       _gemini = geminiClient ?? GeminiVisionClient();

  final GroqApiConfigurationRepository _configs;
  final SecureKeyStore _keys;
  final GroqVisionClient _groq;
  final GeminiVisionClient _gemini;

  bool _busy = false;

  /// Tiny 1×1 PNG — not a customer receipt.
  static final Uint8List syntheticPng = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x02,
    0x00,
    0x00,
    0x00,
    0x90,
    0x77,
    0x53,
    0xDE,
    0x00,
    0x00,
    0x00,
    0x0C,
    0x49,
    0x44,
    0x41,
    0x54,
    0x08,
    0xD7,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0x00,
    0x00,
    0x00,
    0x03,
    0x00,
    0x01,
    0x00,
    0x05,
    0xFE,
    0xD4,
    0xEF,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  Future<ApiTestResult> runConnectionTest(String configId) async {
    if (_busy) {
      return ApiTestResult(
        providerLabel: 'Busy',
        model: '',
        status: ApiTestStatus.testNotCompleted,
        testedAt: DateTime.now().toUtc(),
        explanation: 'Another API test is already running.',
      );
    }
    _busy = true;
    try {
      return await _run(configId, includeVision: false);
    } finally {
      _busy = false;
    }
  }

  Future<ApiTestResult> runVisionTest(String configId) async {
    if (_busy) {
      return ApiTestResult(
        providerLabel: 'Busy',
        model: '',
        status: ApiTestStatus.testNotCompleted,
        testedAt: DateTime.now().toUtc(),
        explanation: 'Another API test is already running.',
      );
    }
    _busy = true;
    try {
      return await _run(configId, includeVision: true);
    } finally {
      _busy = false;
    }
  }

  Future<ApiTestResult> _run(
    String configId, {
    required bool includeVision,
  }) async {
    final config = await _configs.getById(configId);
    final now = DateTime.now().toUtc();
    if (config == null) {
      return ApiTestResult(
        providerLabel: 'Unknown',
        model: '',
        status: ApiTestStatus.testNotCompleted,
        testedAt: now,
        explanation: 'Configuration was not found.',
      );
    }

    final model =
        config.modelHint ??
        (config.providerKind == AiProviderKind.gemini
            ? GeminiConstants.defaultVisionModel
            : GroqConstants.defaultVisionModel);
    final provider = config.providerKind.displayLabel;

    final slot = config.secureKeySlot;
    if (slot == null) {
      return _persist(
        config,
        ApiTestResult(
          providerLabel: provider,
          model: model,
          status: ApiTestStatus.invalidApiKey,
          testedAt: now,
          explanation: 'No secure key is stored for this provider.',
        ),
      );
    }
    final secret = await _keys.read(slot);
    if (secret == null || secret.isEmpty) {
      return _persist(
        config,
        ApiTestResult(
          providerLabel: provider,
          model: model,
          status: ApiTestStatus.invalidApiKey,
          testedAt: now,
          explanation: 'API key missing from secure storage.',
        ),
      );
    }

    try {
      switch (config.providerKind) {
        case AiProviderKind.groq:
        case AiProviderKind.custom:
          await _groq.testKey(
            apiKey: secret,
            endpoint: config.endpoint,
            model: model,
          );
        case AiProviderKind.gemini:
          await _gemini.testConnection(
            apiKey: secret,
            endpoint: config.endpoint,
            model: model,
          );
      }

      var visionOk = false;
      if (includeVision) {
        switch (config.providerKind) {
          case AiProviderKind.groq:
          case AiProviderKind.custom:
            await _groq.extractReceipt(
              apiKey: secret,
              endpoint: config.endpoint,
              model: model,
              imageBytes: syntheticPng,
              mimeType: 'image/png',
              configId: config.id,
              maxCompletionTokensOverride: 128,
            );
          case AiProviderKind.gemini:
            await _gemini.extractReceipt(
              apiKey: secret,
              endpoint: config.endpoint,
              model: model,
              imageBytes: syntheticPng,
              mimeType: 'image/png',
              configId: config.id,
              maxOutputTokens: 128,
            );
        }
        visionOk = true;
      }

      return _persist(
        config,
        ApiTestResult(
          providerLabel: provider,
          model: model,
          status: ApiTestStatus.working,
          testedAt: now,
          authenticationOk: true,
          responseOk: true,
          visionVerified: visionOk,
          explanation: includeVision
              ? 'Authentication, response, and vision support verified '
                    'using a synthetic test image (not a customer receipt).'
              : 'Authentication and basic response verified.',
        ),
      );
    } on GroqFailure catch (failure) {
      final status = _mapFailure(failure);
      return _persist(
        config,
        ApiTestResult(
          providerLabel: provider,
          model: model,
          status: status,
          testedAt: now,
          authenticationOk: status != ApiTestStatus.invalidApiKey,
          responseOk: false,
          visionVerified: false,
          explanation: failure.userFacingMessage,
          diagnostic: failure.message,
        ),
      );
    } catch (error) {
      return _persist(
        config,
        ApiTestResult(
          providerLabel: provider,
          model: model,
          status: ApiTestStatus.providerError,
          testedAt: now,
          explanation: 'Test could not be completed.',
          diagnostic: sanitizeProviderMessage('$error'),
        ),
      );
    }
  }

  ApiTestStatus _mapFailure(GroqFailure failure) {
    return switch (failure.kind) {
      GroqFailureKind.authentication => ApiTestStatus.invalidApiKey,
      GroqFailureKind.rateLimit => ApiTestStatus.rateLimited,
      GroqFailureKind.outputTokenLimit => ApiTestStatus.outputTokenLimit,
      GroqFailureKind.modelUnavailable => ApiTestStatus.unsupportedModel,
      GroqFailureKind.timeout => ApiTestStatus.connectionTimeout,
      GroqFailureKind.network => ApiTestStatus.networkUnavailable,
      GroqFailureKind.imageTooLarge => ApiTestStatus.providerError,
      _ => ApiTestStatus.providerError,
    };
  }

  Future<ApiTestResult> _persist(
    GroqApiConfigurationRecord config,
    ApiTestResult result,
  ) async {
    await _configs.recordTestOutcome(
      id: config.id,
      result: result.status.storageValue,
      detail: result.explanation,
      clearError: result.isWorking,
    );
    return result;
  }
}
