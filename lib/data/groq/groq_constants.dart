/// Official Groq Vision defaults verified from https://console.groq.com/docs/vision
abstract final class GroqConstants {
  static const defaultEndpoint = 'https://api.groq.com/openai/v1';
  static const chatCompletionsPath = '/chat/completions';
  static const defaultVisionModel = 'qwen/qwen3.8-27b';
  static const maxImageBytes = 20 * 1024 * 1024;
  static const maxFallbackAttempts = 3;
  static const requestTimeout = Duration(seconds: 60);

  static const supportedModelChoices = <String>['qwen/qwen3.8-27b'];

  static const extractionSystemPrompt =
      'You extract structured data from Pakistani bank receipts and WhatsApp '
      'screenshots. Banks may include HBL, Meezan, UBL, MCB, Alfalah, Allied '
      'Bank, Bank Al Habib, JazzCash, Easypaisa, or any other name — never '
      'limit yourself to a fixed bank list. Return ONLY a JSON object. '
      'Never invent values. If a field is unclear or missing, use null and '
      'list it in missingFields or uncertainFields. Do not guess amounts, '
      'references, names, or dates.';

  static const extractionUserPrompt =
      'Read this WhatsApp/bank receipt screenshot and return JSON with keys: '
      'bankName, senderBankAccountName, receiverBankAccountName, amount, '
      'currency, transactionReference, transactionDateTime, whatsappSender, '
      'adminMessage, maskedAccountNumbers (string array), uncertainFields '
      '(string array), missingFields (string array), fieldConfidence '
      '(object of 0..1 scores), overallConfidence (0..1 or null), notes. '
      'amount must be a number or null. Prefer PKR when the receipt shows '
      'rupees. Admin message is any office note visible beside the receipt.';
}
