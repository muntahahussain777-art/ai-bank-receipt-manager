/// Classified Groq / network failures. Never include raw API keys.
enum GroqFailureKind {
  authentication,
  rateLimit,
  modelUnavailable,
  timeout,
  network,
  server,
  malformedResponse,
  schemaInvalid,
  imageTooLarge,
  unauthorizedUpload,
  noEnabledKeys,
  cancelled,
  unknown,
}

class GroqFailure implements Exception {
  const GroqFailure({
    required this.kind,
    required this.message,
    this.statusCode,
    this.retryableWithNextKey = false,
    this.configId,
  });

  final GroqFailureKind kind;
  final String message;
  final int? statusCode;

  /// Temporary provider failures eligible for bounded key fallback.
  final bool retryableWithNextKey;
  final String? configId;

  @override
  String toString() => 'GroqFailure($kind, status=$statusCode): $message';

  static GroqFailure fromHttpStatus(
    int statusCode,
    String bodySnippet, {
    String? configId,
  }) {
    final sanitized = sanitizeProviderMessage(bodySnippet);
    if (statusCode == 401 || statusCode == 403) {
      return GroqFailure(
        kind: GroqFailureKind.authentication,
        message: 'API authentication failed ($statusCode). $sanitized',
        statusCode: statusCode,
        // Try the next enabled key; do not bypass quotas.
        retryableWithNextKey: true,
        configId: configId,
      );
    }
    if (statusCode == 429) {
      return GroqFailure(
        kind: GroqFailureKind.rateLimit,
        message: 'Rate limited by provider. $sanitized',
        statusCode: statusCode,
        retryableWithNextKey: true,
        configId: configId,
      );
    }
    if (statusCode == 404 || statusCode == 400) {
      final lower = sanitized.toLowerCase();
      final modelIssue =
          lower.contains('model') ||
          lower.contains('not found') ||
          lower.contains('decommissioned');
      return GroqFailure(
        kind: modelIssue
            ? GroqFailureKind.modelUnavailable
            : GroqFailureKind.unknown,
        message: sanitized.isEmpty
            ? 'Provider rejected the request ($statusCode).'
            : sanitized,
        statusCode: statusCode,
        retryableWithNextKey: modelIssue,
        configId: configId,
      );
    }
    if (statusCode == 408 || statusCode == 502 || statusCode == 503) {
      return GroqFailure(
        kind: statusCode == 408
            ? GroqFailureKind.timeout
            : GroqFailureKind.server,
        message: 'Temporary provider error ($statusCode). $sanitized',
        statusCode: statusCode,
        retryableWithNextKey: true,
        configId: configId,
      );
    }
    return GroqFailure(
      kind: GroqFailureKind.unknown,
      message: 'Unexpected provider status $statusCode. $sanitized',
      statusCode: statusCode,
      retryableWithNextKey: statusCode >= 500,
      configId: configId,
    );
  }
}

/// Strips likely secrets from provider error bodies before storage/logs.
String sanitizeProviderMessage(String raw) {
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length > 280) {
    text = '${text.substring(0, 280)}…';
  }
  return text
      .replaceAll(
        RegExp(r'gsk_[A-Za-z0-9_\-]+'),
        'gsk_***',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAll(
        RegExp(r'api[_-]?key["\s:=]+[A-Za-z0-9_\-]+', caseSensitive: false),
        'api_key=***',
      );
}
