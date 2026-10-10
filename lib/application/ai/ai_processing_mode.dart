/// Single active receipt-processing mode. Exactly one may be selected.
enum AiProcessingMode { groq, gemini, custom, offlineOcr, manual }

extension AiProcessingModeCodec on AiProcessingMode {
  String get storageValue => switch (this) {
    AiProcessingMode.groq => 'groq',
    AiProcessingMode.gemini => 'gemini',
    AiProcessingMode.custom => 'custom',
    AiProcessingMode.offlineOcr => 'offline_ocr',
    AiProcessingMode.manual => 'manual',
  };

  String get displayLabel => switch (this) {
    AiProcessingMode.groq => 'Groq AI',
    AiProcessingMode.gemini => 'Gemini AI',
    AiProcessingMode.custom => 'Custom AI',
    AiProcessingMode.offlineOcr => 'Offline OCR',
    AiProcessingMode.manual => 'Manual Entry',
  };

  bool get usesCloudAi =>
      this == AiProcessingMode.groq ||
      this == AiProcessingMode.gemini ||
      this == AiProcessingMode.custom;

  static AiProcessingMode parse(String? value) {
    return switch (value) {
      'gemini' => AiProcessingMode.gemini,
      'custom' => AiProcessingMode.custom,
      'offline_ocr' => AiProcessingMode.offlineOcr,
      'manual' => AiProcessingMode.manual,
      _ => AiProcessingMode.groq,
    };
  }
}

abstract final class AiSettingsKeys {
  static const processingMode = 'ai_processing_mode';
  static const offlineFallback = 'ai_offline_ocr_fallback';
}
