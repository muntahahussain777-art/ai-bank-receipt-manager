abstract final class DbSchema {
  static const databaseName = 'ai_bank_receipt_manager.db';
  static const version = 7;

  static const receipts = 'receipts';
  static const accountMappings = 'account_mappings';
  static const officeAccountAliases = 'office_account_aliases';
  static const customers = 'customers';
  static const dealers = 'dealers';
  static const customerAliases = 'customer_aliases';
  static const dealerAliases = 'dealer_aliases';
  static const appSettings = 'app_settings';
  static const groqConfigs = 'groq_api_configurations';
  static const receiptAudit = 'receipt_audit_history';
  static const importBatches = 'import_batches';
  static const aiExtractions = 'ai_extractions';
  static const importQueueItems = 'import_queue_items';
  static const reconciliationCases = 'reconciliation_cases';
}
