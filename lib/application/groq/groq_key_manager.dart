import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';

class GroqKeyManager {
  GroqKeyManager({
    required GroqApiConfigurationRepository configs,
    required SecureKeyStore keyStore,
    GroqVisionClient? client,
  }) : _configs = configs,
       _keys = keyStore,
       _client = client ?? GroqVisionClient();

  final GroqApiConfigurationRepository _configs;
  final SecureKeyStore _keys;
  final GroqVisionClient _client;

  Future<List<GroqApiConfigurationRecord>> list() => _configs.listActive();

  Future<GroqApiConfigurationRecord> addKey({
    required String label,
    required String apiKey,
    String? endpoint,
    String? modelHint,
    bool setPreferred = false,
    bool enabled = true,
    AiProviderKind providerKind = AiProviderKind.groq,
    int? timeoutSeconds,
    int? maxCompletionTokens,
  }) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('API key must not be empty.');
    }
    final defaultEndpoint = providerKind == AiProviderKind.gemini
        ? 'https://generativelanguage.googleapis.com/v1beta'
        : GroqConstants.defaultEndpoint;
    final defaultModel = providerKind == AiProviderKind.gemini
        ? 'gemini-2.0-flash'
        : GroqConstants.defaultVisionModel;
    final record = await _configs.create(
      label: label.trim().isEmpty ? providerKind.displayLabel : label.trim(),
      endpoint: (endpoint ?? defaultEndpoint).trim(),
      modelHint: modelHint ?? defaultModel,
      maskedKeyHint: maskApiKey(trimmed),
      isActive: setPreferred,
      isEnabled: enabled,
      providerKind: providerKind,
      timeoutSeconds: timeoutSeconds,
      maxCompletionTokens: maxCompletionTokens,
    );
    await _keys.write(record.secureKeySlot!, trimmed);
    return record;
  }

  Future<GroqApiConfigurationRecord> rename({
    required String id,
    required String label,
  }) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      throw StateError('Key configuration was not found.');
    }
    return _configs.update(existing.copyWith(label: label.trim()));
  }

  Future<GroqApiConfigurationRecord> setEnabled({
    required String id,
    required bool enabled,
  }) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      throw StateError('Key configuration was not found.');
    }
    return _configs.update(existing.copyWith(isEnabled: enabled));
  }

  Future<GroqApiConfigurationRecord> setPreferred(String id) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      throw StateError('Key configuration was not found.');
    }
    return _configs.update(existing.copyWith(isActive: true, isEnabled: true));
  }

  Future<GroqApiConfigurationRecord> updateModel({
    required String id,
    required String model,
  }) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      throw StateError('Key configuration was not found.');
    }
    return _configs.update(existing.copyWith(modelHint: model));
  }

  Future<void> deleteKey(String id) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      return;
    }
    final slot = existing.secureKeySlot;
    if (slot != null) {
      await _keys.delete(slot);
    }
    await _configs.softDelete(id);
  }

  Future<String?> maskedSecret(String id) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      return null;
    }
    return existing.maskedKeyHint ?? '(no key)';
  }

  Future<GroqApiConfigurationRecord> testKey(String id) async {
    final existing = await _configs.getById(id);
    if (existing == null) {
      throw StateError('Key configuration was not found.');
    }
    final slot = existing.secureKeySlot;
    if (slot == null) {
      throw const GroqFailure(
        kind: GroqFailureKind.authentication,
        message: 'No secure key slot configured.',
      );
    }
    final secret = await _keys.read(slot);
    if (secret == null || secret.isEmpty) {
      throw const GroqFailure(
        kind: GroqFailureKind.authentication,
        message: 'API key missing from secure storage.',
      );
    }
    try {
      await _client.testKey(
        apiKey: secret,
        endpoint: existing.endpoint,
        model: existing.modelHint ?? GroqConstants.defaultVisionModel,
      );
      return _configs.recordTestSuccess(id);
    } on GroqFailure catch (failure) {
      await _configs.recordError(id: id, status: failure.kind.name);
      rethrow;
    }
  }

  Future<ResolvedGroqKey?> resolveSecret(
    GroqApiConfigurationRecord config,
  ) async {
    final slot = config.secureKeySlot;
    if (slot == null) {
      return null;
    }
    final secret = await _keys.read(slot);
    if (secret == null || secret.isEmpty) {
      return null;
    }
    return ResolvedGroqKey(config: config, apiKey: secret);
  }
}

class ResolvedGroqKey {
  const ResolvedGroqKey({required this.config, required this.apiKey});

  final GroqApiConfigurationRecord config;
  final String apiKey;
}
