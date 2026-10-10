abstract final class GeminiConstants {
  static const defaultEndpoint =
      'https://generativelanguage.googleapis.com/v1beta';
  static const defaultVisionModel = 'gemini-2.0-flash';
  static const supportedModelChoices = <String>[
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
  ];
  static const defaultMaxOutputTokens = 700;
  static const requestTimeout = Duration(seconds: 45);
}
