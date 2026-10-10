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
      'You extract structured data from Pakistani bank-receipt WhatsApp '
      'screenshots. Analyze the FULL image: the bank receipt area AND any '
      'visible WhatsApp message/caption underneath or beside it separately. '
      'Banks may include HBL, Meezan, UBL, MCB, Alfalah, Allied Bank, Bank Al '
      'Habib, JazzCash, Easypaisa, or any other name. Return ONLY a JSON '
      'object. Never invent values. If a field is unclear or not visible, use '
      'null and list it in missingFields or uncertainFields. '
      'Bank sender, bank receiver, WhatsApp sender, and the accounting '
      'customer/dealer from the admin note are DIFFERENT roles — never mix '
      'them. Do not treat the WhatsApp forwarder as the customer. Do not '
      'treat the bank sender as the customer unless the admin note clearly '
      'says so. Admin notes may be English, Urdu, Roman Urdu, or mixed.';

  static const extractionUserPrompt =
      'Read this WhatsApp bank-receipt screenshot and return JSON with keys: '
      'bankName, bankSenderName, bankReceiverName, senderBankAccountName, '
      'receiverBankAccountName, amount, currency, transactionReference, '
      'transactionDateTime, whatsappSender, whatsappMessage, adminMessage, '
      'suggestedCustomerName, suggestedDealerName, suggestedOfficeAccountName, '
      'bankDirectionHint, maskedAccountNumbers (string array), uncertainFields '
      '(string array), missingFields (string array), fieldConfidence '
      '(object of 0..1 scores), overallConfidence (0..1 or null), notes. '
      'Use bankSenderName/bankReceiverName OR senderBankAccountName/'
      'receiverBankAccountName (same meaning). Put the visible WhatsApp admin '
      'caption in both whatsappMessage and adminMessage when present. '
      'suggestedCustomerName / suggestedDealerName / suggestedOfficeAccountName '
      'are ONLY text hints from the admin note (e.g. "Ye Rashid ke paise hain" '
      '→ suggestedCustomerName "Rashid"); never invent people who are not '
      'written. bankDirectionHint is credit/debit/received/sent/incoming/'
      'outgoing only when clearly shown on the bank receipt, else null. '
      'amount must be a number or null. Prefer PKR when the receipt shows '
      'rupees. If the WhatsApp message is not visible, leave those fields null.';
}
