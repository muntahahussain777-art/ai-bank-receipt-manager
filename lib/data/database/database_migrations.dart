import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/utils/alias_normalize.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Versioned migrations. Never drop user tables or wipe the database.
abstract final class DatabaseMigrations {
  static Future<void> onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await _createV1(txn);
      await _migrateToV2(txn);
      await _seedDefaultOfficeAccountsOnce(txn);
      await _migrateToV3(txn);
      await _migrateToV4(txn);
      await _migrateToV5(txn);
      await _migrateToV6(txn);
    });
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.transaction((txn) async {
      if (oldVersion < 2) {
        await _migrateToV2(txn);
        await _seedDefaultOfficeAccountsOnce(txn);
      }
      if (oldVersion < 3) {
        await _migrateToV3(txn);
      }
      if (oldVersion < 4) {
        await _migrateToV4(txn);
      }
      if (oldVersion < 5) {
        await _migrateToV5(txn);
      }
      if (oldVersion < 6) {
        await _migrateToV6(txn);
      }
    });
  }

  static Future<void> onDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Refuse destructive downgrades. Keep the existing schema.
  }

  static Future<void> _createV1(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE ${DbSchema.accountMappings} (
  id TEXT PRIMARY KEY NOT NULL,
  office_key TEXT NOT NULL UNIQUE,
  short_name TEXT NOT NULL,
  legal_name TEXT NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.customers} (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  usual_account_id TEXT,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (usual_account_id) REFERENCES ${DbSchema.accountMappings}(id)
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.dealers} (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  usual_account_id TEXT,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (usual_account_id) REFERENCES ${DbSchema.accountMappings}(id)
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.importBatches} (
  id TEXT PRIMARY KEY NOT NULL,
  accounting_date TEXT NOT NULL,
  imported_at TEXT NOT NULL,
  source TEXT NOT NULL,
  receipt_count INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.receipts} (
  id TEXT PRIMARY KEY NOT NULL,
  transaction_id TEXT,
  bank_name TEXT NOT NULL,
  bank_sender_name TEXT,
  bank_receiver_name TEXT,
  amount REAL NOT NULL,
  currency TEXT NOT NULL,
  transaction_date_time TEXT,
  accounting_date TEXT NOT NULL,
  imported_at TEXT NOT NULL,
  whatsapp_message_date_time TEXT,
  whatsapp_sender TEXT,
  admin_message TEXT,
  original_image_path TEXT,
  image_hash TEXT,
  receipt_type TEXT NOT NULL,
  mapped_party_id TEXT,
  mapped_account_id TEXT,
  dealer_id TEXT,
  customer_id TEXT,
  confidence_score REAL,
  review_status TEXT NOT NULL,
  entry_status TEXT NOT NULL,
  entered_at TEXT,
  entered_by TEXT,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  import_batch_id TEXT,
  FOREIGN KEY (mapped_account_id) REFERENCES ${DbSchema.accountMappings}(id),
  FOREIGN KEY (dealer_id) REFERENCES ${DbSchema.dealers}(id),
  FOREIGN KEY (customer_id) REFERENCES ${DbSchema.customers}(id),
  FOREIGN KEY (import_batch_id) REFERENCES ${DbSchema.importBatches}(id),
  CHECK (amount >= 0),
  CHECK (receipt_type IN ('received', 'sent', 'unknown')),
  CHECK (entry_status IN ('pending', 'entered')),
  CHECK (review_status IN ('pending_review', 'approved', 'needs_reconciliation', 'rejected'))
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.appSettings} (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.groqConfigs} (
  id TEXT PRIMARY KEY NOT NULL,
  label TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  model_hint TEXT,
  secure_key_slot TEXT,
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)
''');

    await db.execute('''
CREATE TABLE ${DbSchema.receiptAudit} (
  id TEXT PRIMARY KEY NOT NULL,
  receipt_id TEXT NOT NULL,
  field_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  changed_at TEXT NOT NULL,
  changed_by TEXT,
  reason TEXT,
  FOREIGN KEY (receipt_id) REFERENCES ${DbSchema.receipts}(id)
)
''');

    await db.execute(
      'CREATE INDEX idx_receipts_accounting_date ON ${DbSchema.receipts}(accounting_date)',
    );
    await db.execute(
      'CREATE INDEX idx_receipts_entry_status ON ${DbSchema.receipts}(entry_status)',
    );
    await db.execute(
      'CREATE INDEX idx_receipts_deleted_at ON ${DbSchema.receipts}(deleted_at)',
    );
    await db.execute(
      'CREATE INDEX idx_receipts_transaction_id ON ${DbSchema.receipts}(transaction_id)',
    );
    await db.execute(
      'CREATE INDEX idx_receipts_image_hash ON ${DbSchema.receipts}(image_hash)',
    );
    await db.execute(
      'CREATE INDEX idx_receipts_bank_amount_date ON ${DbSchema.receipts}(bank_name, amount, accounting_date)',
    );
    await db.execute(
      'CREATE INDEX idx_audit_receipt_id ON ${DbSchema.receiptAudit}(receipt_id)',
    );
    await db.execute(
      'CREATE INDEX idx_import_batches_accounting_date ON ${DbSchema.importBatches}(accounting_date)',
    );
    await db.execute(
      'CREATE INDEX idx_customers_deleted_at ON ${DbSchema.customers}(deleted_at)',
    );
    await db.execute(
      'CREATE INDEX idx_dealers_deleted_at ON ${DbSchema.dealers}(deleted_at)',
    );
  }

  static Future<void> _migrateToV2(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      DbSchema.accountMappings,
      'display_name',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.accountMappings,
      'status',
      "TEXT NOT NULL DEFAULT 'active'",
    );
    await _addColumnIfMissing(
      db,
      DbSchema.accountMappings,
      'archived_at',
      'TEXT',
    );

    // Make office_key nullable for user-created accounts (SQLite cannot drop
    // NOT NULL easily; new inserts may use a generated unique key).
    await db.execute('''
UPDATE ${DbSchema.accountMappings}
SET display_name = short_name
WHERE display_name IS NULL OR TRIM(display_name) = ''
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbSchema.officeAccountAliases} (
  id TEXT PRIMARY KEY NOT NULL,
  office_account_id TEXT NOT NULL,
  alias_name TEXT NOT NULL,
  normalized_alias TEXT NOT NULL,
  approval_status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (office_account_id) REFERENCES ${DbSchema.accountMappings}(id),
  CHECK (approval_status IN ('pending', 'approved', 'rejected'))
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbSchema.customerAliases} (
  id TEXT PRIMARY KEY NOT NULL,
  customer_id TEXT NOT NULL,
  alias_name TEXT NOT NULL,
  normalized_alias TEXT NOT NULL,
  approval_status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (customer_id) REFERENCES ${DbSchema.customers}(id),
  CHECK (approval_status IN ('pending', 'approved', 'rejected'))
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbSchema.dealerAliases} (
  id TEXT PRIMARY KEY NOT NULL,
  dealer_id TEXT NOT NULL,
  alias_name TEXT NOT NULL,
  normalized_alias TEXT NOT NULL,
  approval_status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (dealer_id) REFERENCES ${DbSchema.dealers}(id),
  CHECK (approval_status IN ('pending', 'approved', 'rejected'))
)
''');

    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'proposed_office_flow',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'classification_notes',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'needs_review',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_office_aliases_account ON ${DbSchema.officeAccountAliases}(office_account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_office_aliases_normalized ON ${DbSchema.officeAccountAliases}(normalized_alias)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_aliases_owner ON ${DbSchema.customerAliases}(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dealer_aliases_owner ON ${DbSchema.dealerAliases}(dealer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_account_mappings_status ON ${DbSchema.accountMappings}(status)',
    );

    // Backfill approved bank aliases from legacy legal_name when none exist.
    final accounts = await db.query(
      DbSchema.accountMappings,
      columns: ['id', 'legal_name', 'display_name', 'short_name'],
    );
    final uuid = const Uuid();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final account in accounts) {
      final id = account['id']! as String;
      final existing = await db.query(
        DbSchema.officeAccountAliases,
        where: 'office_account_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        continue;
      }
      final legal = (account['legal_name'] as String?)?.trim() ?? '';
      if (legal.isEmpty) {
        continue;
      }
      await db.insert(DbSchema.officeAccountAliases, {
        'id': uuid.v4(),
        'office_account_id': id,
        'alias_name': legal,
        'normalized_alias': normalizeAlias(legal),
        'approval_status': 'approved',
        'created_at': now,
      });
    }
  }

  /// Seeds Mutalib / AD only once. Never recreates deleted defaults.
  static Future<void> _seedDefaultOfficeAccountsOnce(
    DatabaseExecutor db,
  ) async {
    final flagged = await db.query(
      DbSchema.appSettings,
      where: 'key = ?',
      whereArgs: [DefaultOfficeAccountIds.seedFlagKey],
      limit: 1,
    );
    if (flagged.isNotEmpty) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(DbSchema.accountMappings, {
      'id': DefaultOfficeAccountIds.mutalib,
      'office_key': 'mutalib',
      'short_name': 'Mutalib',
      'legal_name': 'Azlan Traders',
      'display_name': 'Mutalib',
      'status': 'active',
      'notes': 'Default office account. Editable. Not a permanent identity.',
      'created_at': now,
      'updated_at': now,
      'archived_at': null,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert(DbSchema.accountMappings, {
      'id': DefaultOfficeAccountIds.ad,
      'office_key': 'ad',
      'short_name': 'AD',
      'legal_name': 'Habib Enterprise',
      'display_name': 'AD',
      'status': 'active',
      'notes': 'Default office account. Editable. Not a permanent identity.',
      'created_at': now,
      'updated_at': now,
      'archived_at': null,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await _ensureAlias(
      db,
      accountId: DefaultOfficeAccountIds.mutalib,
      aliasName: 'Azlan Traders',
      now: now,
    );
    await _ensureAlias(
      db,
      accountId: DefaultOfficeAccountIds.ad,
      aliasName: 'Habib Enterprise',
      now: now,
    );

    await db.insert(DbSchema.appSettings, {
      'key': DefaultOfficeAccountIds.seedFlagKey,
      'value': '1',
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _ensureAlias(
    DatabaseExecutor db, {
    required String accountId,
    required String aliasName,
    required String now,
  }) async {
    final normalized = normalizeAlias(aliasName);
    final rows = await db.query(
      DbSchema.officeAccountAliases,
      where: 'office_account_id = ? AND normalized_alias = ?',
      whereArgs: [accountId, normalized],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return;
    }
    // Only add if the account row still exists (not permanently deleted).
    final account = await db.query(
      DbSchema.accountMappings,
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (account.isEmpty) {
      return;
    }
    await db.insert(DbSchema.officeAccountAliases, {
      'id': const Uuid().v4(),
      'office_account_id': accountId,
      'alias_name': aliasName,
      'normalized_alias': normalized,
      'approval_status': 'approved',
      'created_at': now,
    });
  }

  static Future<void> _migrateToV3(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      DbSchema.groqConfigs,
      'is_enabled',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.groqConfigs,
      'masked_key_hint',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.groqConfigs,
      'last_error_status',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.groqConfigs,
      'last_error_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.groqConfigs,
      'last_tested_at',
      'TEXT',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbSchema.aiExtractions} (
  id TEXT PRIMARY KEY NOT NULL,
  receipt_id TEXT,
  image_path TEXT NOT NULL,
  image_hash TEXT,
  raw_ai_json TEXT,
  raw_parse_status TEXT,
  processing_status TEXT NOT NULL,
  error_code TEXT,
  error_message TEXT,
  model_used TEXT,
  key_config_id TEXT,
  proposed_json TEXT,
  user_corrected_json TEXT,
  applied_to_receipt INTEGER NOT NULL DEFAULT 0,
  authorization_granted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (receipt_id) REFERENCES ${DbSchema.receipts}(id),
  CHECK (processing_status IN (
    'pending', 'succeeded', 'failed', 'needs_review', 'proposed'
  ))
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_extractions_receipt '
      'ON ${DbSchema.aiExtractions}(receipt_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_extractions_status '
      'ON ${DbSchema.aiExtractions}(processing_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_extractions_hash '
      'ON ${DbSchema.aiExtractions}(image_hash)',
    );
  }

  static Future<void> _migrateToV4(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      DbSchema.importBatches,
      'file_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.importBatches,
      'success_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.importBatches,
      'failed_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.importBatches,
      'duplicate_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.importBatches,
      'pending_review_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.importBatches,
      'batch_status',
      "TEXT NOT NULL DEFAULT 'open'",
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbSchema.importQueueItems} (
  id TEXT PRIMARY KEY NOT NULL,
  batch_id TEXT NOT NULL,
  group_id TEXT,
  source_kind TEXT NOT NULL,
  original_uri TEXT,
  stored_path TEXT NOT NULL,
  image_hash TEXT,
  mime_type TEXT,
  display_name TEXT,
  queue_status TEXT NOT NULL,
  error_message TEXT,
  extraction_id TEXT,
  receipt_id TEXT,
  duplicate_of_receipt_id TEXT,
  admin_note_override TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (batch_id) REFERENCES ${DbSchema.importBatches}(id),
  CHECK (queue_status IN (
    'queued', 'processing', 'awaiting_review', 'succeeded',
    'failed', 'skipped_duplicate', 'cancelled'
  ))
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_queue_batch '
      'ON ${DbSchema.importQueueItems}(batch_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_queue_status '
      'ON ${DbSchema.importQueueItems}(queue_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_queue_group '
      'ON ${DbSchema.importQueueItems}(group_id)',
    );

    // Backfill file_count from legacy receipt_count when unset.
    await db.execute('''
UPDATE ${DbSchema.importBatches}
SET file_count = receipt_count
WHERE file_count = 0 AND receipt_count > 0
''');
  }

  static Future<void> _migrateToV5(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'winforms_reference',
      'TEXT',
    );
    await _addColumnIfMissing(db, DbSchema.receipts, 'prior_amount', 'REAL');
    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'prior_party_name',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'prior_account_id',
      'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipts_bank_name '
      'ON ${DbSchema.receipts}(bank_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipts_mapped_account '
      'ON ${DbSchema.receipts}(mapped_account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipts_customer '
      'ON ${DbSchema.receipts}(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipts_dealer '
      'ON ${DbSchema.receipts}(dealer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipts_review_status '
      'ON ${DbSchema.receipts}(review_status)',
    );
  }

  static Future<void> _migrateToV6(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      DbSchema.receipts,
      'reconciliation_completed_at',
      'TEXT',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbSchema.reconciliationCases} (
  id TEXT PRIMARY KEY NOT NULL,
  receipt_id TEXT NOT NULL,
  status TEXT NOT NULL,
  kind TEXT NOT NULL,
  reason TEXT NOT NULL,
  correction_notes TEXT,
  diffs_json TEXT NOT NULL,
  previous_amount REAL,
  corrected_amount REAL,
  opened_at TEXT NOT NULL,
  opened_by TEXT,
  completed_at TEXT,
  completed_by TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(receipt_id) REFERENCES ${DbSchema.receipts}(id)
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recon_cases_receipt '
      'ON ${DbSchema.reconciliationCases}(receipt_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recon_cases_status '
      'ON ${DbSchema.reconciliationCases}(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recon_cases_opened '
      'ON ${DbSchema.reconciliationCases}(opened_at)',
    );
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String typeSql,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (exists) {
      return;
    }
    await db.execute('ALTER TABLE $table ADD COLUMN $column $typeSql');
  }
}
