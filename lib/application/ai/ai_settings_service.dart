import 'package:ai_bank_receipt_manager/application/ai/ai_processing_mode.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';

class AiSettingsService {
  AiSettingsService(this._settings);

  final AppSettingsRepository _settings;

  Future<AiProcessingMode> getProcessingMode() async {
    final raw = await _settings.get(AiSettingsKeys.processingMode);
    return AiProcessingModeCodec.parse(raw);
  }

  Future<void> setProcessingMode(AiProcessingMode mode) {
    return _settings.set(AiSettingsKeys.processingMode, mode.storageValue);
  }

  /// Default true: automatically use Offline OCR when selected cloud AI fails.
  Future<bool> getOfflineFallbackEnabled() async {
    final raw = await _settings.get(AiSettingsKeys.offlineFallback);
    if (raw == null) {
      return true;
    }
    return raw == '1' || raw.toLowerCase() == 'true';
  }

  Future<void> setOfflineFallbackEnabled(bool enabled) {
    return _settings.set(
      AiSettingsKeys.offlineFallback,
      enabled ? 'true' : 'false',
    );
  }
}
