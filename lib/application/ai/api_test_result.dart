enum ApiTestStatus {
  working,
  invalidApiKey,
  rateLimited,
  quotaExhausted,
  unsupportedModel,
  visionNotSupported,
  networkUnavailable,
  connectionTimeout,
  providerError,
  outputTokenLimit,
  testNotCompleted,
}

extension ApiTestStatusLabel on ApiTestStatus {
  String get label => switch (this) {
    ApiTestStatus.working => 'Working',
    ApiTestStatus.invalidApiKey => 'Invalid API Key',
    ApiTestStatus.rateLimited => 'Rate Limited',
    ApiTestStatus.quotaExhausted => 'Quota Exhausted',
    ApiTestStatus.unsupportedModel => 'Unsupported Model',
    ApiTestStatus.visionNotSupported => 'Vision Not Supported',
    ApiTestStatus.networkUnavailable => 'Network Unavailable',
    ApiTestStatus.connectionTimeout => 'Connection Timeout',
    ApiTestStatus.providerError => 'Provider Error',
    ApiTestStatus.outputTokenLimit => 'Output Token Limit',
    ApiTestStatus.testNotCompleted => 'Test Not Completed',
  };

  String get storageValue => name;
}

class ApiTestResult {
  const ApiTestResult({
    required this.providerLabel,
    required this.model,
    required this.status,
    required this.testedAt,
    this.authenticationOk = false,
    this.responseOk = false,
    this.visionVerified = false,
    this.explanation = '',
    this.diagnostic = '',
  });

  final String providerLabel;
  final String model;
  final ApiTestStatus status;
  final DateTime testedAt;
  final bool authenticationOk;
  final bool responseOk;
  final bool visionVerified;
  final String explanation;

  /// Sanitized diagnostic — never full secrets.
  final String diagnostic;

  bool get isWorking => status == ApiTestStatus.working;
}
