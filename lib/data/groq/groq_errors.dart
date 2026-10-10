/// Classified Groq / network failures. Never include raw API keys.
enum GroqFailureKind {
  authentication,
  rateLimit,
  outputTokenLimit,
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
    this.retryAfter,
    this.configId,
  });

  final GroqFailureKind kind;

  /// Sanitized diagnostic detail for troubleshooting / logs.
  final String message;
  final int? statusCode;

  /// Temporary provider failures eligible for bounded key fallback.
  /// Never true for OTPM / output-token budget misconfiguration.
  final bool retryableWithNextKey;
  final Duration? retryAfter;
  final String? configId;

  /// Safe message for ordinary user-facing UI.
  String get userFacingMessage {
    switch (kind) {
      case GroqFailureKind.rateLimit:
      case GroqFailureKind.outputTokenLimit:
      case GroqFailureKind.timeout:
      case GroqFailureKind.network:
      case GroqFailureKind.server:
        return GroqUserMessages.temporaryUnavailable;
      case GroqFailureKind.authentication:
        return 'AI authentication failed. Check the API key in settings, '
            'or enter receipt details manually.';
      case GroqFailureKind.noEnabledKeys:
        return 'No AI key is configured. Enter receipt details manually, '
            'or add a key in settings.';
      case GroqFailureKind.modelUnavailable:
        return 'The selected AI model is unavailable. Choose another model '
            'in settings, or enter receipt details manually.';
      case GroqFailureKind.imageTooLarge:
        return 'This image is too large for AI processing. '
            'Try a smaller photo or enter details manually.';
      case GroqFailureKind.unauthorizedUpload:
        return 'AI upload was not authorized.';
      case GroqFailureKind.malformedResponse:
      case GroqFailureKind.schemaInvalid:
        return 'AI returned incomplete data. Please review and enter '
            'receipt details manually.';
      case GroqFailureKind.cancelled:
        return 'AI processing was cancelled.';
      case GroqFailureKind.unknown:
        return GroqUserMessages.temporaryUnavailable;
    }
  }

  @override
  String toString() => 'GroqFailure($kind, status=$statusCode): $message';

  static GroqFailure fromHttpStatus(
    int statusCode,
    String bodySnippet, {
    String? configId,
    Map<String, String>? headers,
  }) {
    final sanitized = sanitizeProviderMessage(bodySnippet);
    final lower = sanitized.toLowerCase();
    final retryAfter = parseRetryAfter(headers);

    if (statusCode == 401 || statusCode == 403) {
      return GroqFailure(
        kind: GroqFailureKind.authentication,
        message: 'API authentication failed ($statusCode). $sanitized',
        statusCode: statusCode,
        retryableWithNextKey: true,
        configId: configId,
      );
    }

    if (_isOutputTokenLimit(lower)) {
      // Requested completion budget exceeds remaining OTPM — do not rotate keys
      // or retry the same oversized request.
      return GroqFailure(
        kind: GroqFailureKind.outputTokenLimit,
        message: sanitized.isEmpty
            ? 'Output token budget exceeded for this model/request.'
            : sanitized,
        statusCode: statusCode,
        retryableWithNextKey: false,
        retryAfter: retryAfter,
        configId: configId,
      );
    }

    if (statusCode == 429) {
      return GroqFailure(
        kind: GroqFailureKind.rateLimit,
        message: 'Rate limited by provider. $sanitized',
        statusCode: statusCode,
        // Ordinary RPM/TPM may recover; OTPM oversized requests are handled above.
        retryableWithNextKey: true,
        retryAfter: retryAfter,
        configId: configId,
      );
    }
    if (statusCode == 404 || statusCode == 400) {
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
        retryAfter: retryAfter,
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

  static bool _isOutputTokenLimit(String lower) {
    return lower.contains('otpm') ||
        lower.contains('output tokens per minute') ||
        lower.contains('output_tokens_per_minute') ||
        (lower.contains('output token') && lower.contains('limit')) ||
        (lower.contains('requested') &&
            lower.contains('limit') &&
            lower.contains('token') &&
            lower.contains('output'));
  }
}

abstract final class GroqUserMessages {
  static const temporaryUnavailable =
      'AI processing is temporarily unavailable. Please retry or enter '
      'receipt details manually.';
}

/// Strips likely secrets and org noise from provider error bodies.
String sanitizeProviderMessage(String raw) {
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Drop verbose JSON wrapper noise for UI diagnostics.
  text = text
      .replaceAll(RegExp(r'\{?"error"\s*:\s*\{?', caseSensitive: false), '')
      .replaceAll(RegExp(r'"type"\s*:\s*"[^"]*"', caseSensitive: false), '')
      .replaceAll(RegExp(r'"code"\s*:\s*"[^"]*"', caseSensitive: false), '')
      .replaceAll(RegExp(r'org_[A-Za-z0-9]+'), 'org_***')
      .replaceAll(RegExp(r'gsk_[A-Za-z0-9_\-]+'), 'gsk_***')
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAll(
        RegExp(r'api[_-]?key["\s:=]+[A-Za-z0-9_\-]+', caseSensitive: false),
        'api_key=***',
      )
      .replaceAll(RegExp(r'[{}\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.length > 220) {
    text = '${text.substring(0, 220)}…';
  }
  return text;
}

Duration? parseRetryAfter(Map<String, String>? headers) {
  if (headers == null) {
    return null;
  }
  final raw =
      headers['retry-after'] ??
      headers['Retry-After'] ??
      headers['RETRY-AFTER'];
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final seconds = int.tryParse(raw.trim());
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds);
  }
  return null;
}
