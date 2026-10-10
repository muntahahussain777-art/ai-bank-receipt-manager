/// Official Groq Vision defaults verified from https://console.groq.com/docs/vision
abstract final class GroqConstants {
  static const defaultEndpoint = 'https://api.groq.com/openai/v1';
  static const chatCompletionsPath = '/chat/completions';
  static const defaultVisionModel = 'qwen/qwen3.8-27b';
  static const maxImageBytes = 20 * 1024 * 1024;
  static const maxFallbackAttempts = 3;
  static const requestTimeout = Duration(seconds: 60);

  /// Conservative default under observed 1000 OTPM headroom.
  /// Per-model overrides live in [profileForModel].
  static const defaultMaxCompletionTokens = 700;

  static const supportedModelChoices = <String>['qwen/qwen3.8-27b'];

  static GroqModelProfile profileForModel(String model) {
    final normalized = model.trim().toLowerCase();
    if (normalized == 'qwen/qwen3.8-27b' ||
        normalized.contains('qwen3.8') ||
        normalized.contains('qwen3-8')) {
      return const GroqModelProfile(
        modelId: defaultVisionModel,
        maxCompletionTokens: 700,
        // Thinking tokens inflate OTPM; instruct/JSON extraction must stay compact.
        reasoningEffort: 'none',
        supportsVision: true,
      );
    }
    return GroqModelProfile(
      modelId: model,
      maxCompletionTokens: defaultMaxCompletionTokens,
      reasoningEffort: null,
      supportsVision: true,
    );
  }

  static const extractionSystemPrompt =
      'Extract Pakistani bank-receipt data from the FULL WhatsApp screenshot. '
      'Separate bank receipt fields from any visible WhatsApp caption/admin note. '
      'Return ONLY compact JSON. No explanations, no reasoning, no markdown. '
      'Never invent missing values — use null. '
      'Bank sender, bank receiver, WhatsApp sender, and accounting '
      'customer/dealer from the admin note are different roles — never mix them.';

  static const extractionUserPrompt =
      'Return JSON keys only: '
      'bankName,bankSenderName,bankReceiverName,senderBankAccountName,'
      'receiverBankAccountName,amount,currency,transactionReference,'
      'transactionDateTime,whatsappSender,whatsappMessage,adminMessage,'
      'suggestedCustomerName,suggestedDealerName,suggestedOfficeAccountName,'
      'bankDirectionHint,maskedAccountNumbers,uncertainFields,missingFields,'
      'fieldConfidence,overallConfidence,notes. '
      'bankSenderName/bankReceiverName equal senderBankAccountName/'
      'receiverBankAccountName. '
      'Put visible admin caption in whatsappMessage and adminMessage. '
      'suggested* are text hints from the admin note only '
      '(e.g. "Ye Rashid ke paise hain" → suggestedCustomerName "Rashid"). '
      'bankDirectionHint: credit|debit|received|sent|incoming|outgoing|null. '
      'amount: number|null. Prefer PKR. Keep arrays/objects tiny. '
      'If WhatsApp text is not visible, leave those fields null.';
}

/// Per-model request budget and vision flags.
class GroqModelProfile {
  const GroqModelProfile({
    required this.modelId,
    required this.maxCompletionTokens,
    required this.supportsVision,
    this.reasoningEffort,
  });

  final String modelId;
  final int maxCompletionTokens;
  final String? reasoningEffort;
  final bool supportsVision;
}
