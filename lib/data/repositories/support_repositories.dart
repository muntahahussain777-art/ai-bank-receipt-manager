import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class AppSettingsRepository {
  AppSettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.appSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    final record = AppSettingRecord(
      key: key,
      value: value,
      updatedAt: DateTime.now().toUtc(),
    );
    await db.insert(
      DbSchema.appSettings,
      AppSettingMapper.toMap(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AppSettingRecord>> listAll() async {
    final db = await _db.database;
    final rows = await db.query(DbSchema.appSettings, orderBy: 'key ASC');
    return rows.map(AppSettingMapper.fromMap).toList();
  }
}

class GroqApiConfigurationRepository {
  GroqApiConfigurationRepository(this._db, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<GroqApiConfigurationRecord>> listActive() async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.groqConfigs,
      where: 'deleted_at IS NULL',
      orderBy: 'is_active DESC, label ASC',
    );
    return rows.map(GroqConfigMapper.fromMap).toList();
  }

  Future<GroqApiConfigurationRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.groqConfigs,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return GroqConfigMapper.fromMap(rows.first);
  }

  /// Enabled keys for fallback: preferred first, then others by label.
  Future<List<GroqApiConfigurationRecord>> listEnabledForFallback() async {
    final all = await listActive();
    return [
      for (final config in all)
        if (config.isEnabled &&
            config.secureKeySlot != null &&
            config.secureKeySlot!.isNotEmpty)
          config,
    ];
  }

  Future<List<GroqApiConfigurationRecord>> listByProvider(
    AiProviderKind kind,
  ) async {
    final all = await listActive();
    return [
      for (final c in all)
        if (c.providerKind == kind) c,
    ];
  }

  Future<List<GroqApiConfigurationRecord>> listEnabledForProvider(
    AiProviderKind kind,
  ) async {
    final all = await listEnabledForFallback();
    return [
      for (final c in all)
        if (c.providerKind == kind) c,
    ];
  }

  Future<GroqApiConfigurationRecord> create({
    required String label,
    required String endpoint,
    String? modelHint,
    String? secureKeySlot,
    String? maskedKeyHint,
    bool isActive = false,
    bool isEnabled = true,
    AiProviderKind providerKind = AiProviderKind.groq,
    int? timeoutSeconds,
    int? maxCompletionTokens,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final prefix = switch (providerKind) {
      AiProviderKind.groq => 'groq_key_',
      AiProviderKind.gemini => 'gemini_key_',
      AiProviderKind.custom => 'custom_key_',
    };
    final record = GroqApiConfigurationRecord(
      id: id,
      label: label,
      endpoint: endpoint,
      modelHint: modelHint,
      secureKeySlot: secureKeySlot ?? '$prefix$id',
      maskedKeyHint: maskedKeyHint,
      isActive: isActive,
      isEnabled: isEnabled,
      providerKind: providerKind,
      timeoutSeconds: timeoutSeconds,
      maxCompletionTokens: maxCompletionTokens,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      if (isActive) {
        await txn.update(DbSchema.groqConfigs, {
          'is_active': 0,
          'updated_at': encodeDateTime(now),
        });
      }
      await txn.insert(DbSchema.groqConfigs, GroqConfigMapper.toMap(record));
    });
    return record;
  }

  Future<GroqApiConfigurationRecord> update(
    GroqApiConfigurationRecord record,
  ) async {
    final now = DateTime.now().toUtc();
    final saved = record.copyWith(updatedAt: now);
    final db = await _db.database;
    await db.transaction((txn) async {
      if (saved.isActive) {
        await txn.update(DbSchema.groqConfigs, {
          'is_active': 0,
          'updated_at': encodeDateTime(now),
        });
      }
      await txn.update(
        DbSchema.groqConfigs,
        GroqConfigMapper.toMap(saved),
        where: 'id = ?',
        whereArgs: [saved.id],
      );
    });
    return saved;
  }

  Future<void> softDelete(String id) async {
    final db = await _db.database;
    await db.update(
      DbSchema.groqConfigs,
      {'deleted_at': encodeDateTime(DateTime.now().toUtc()), 'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<GroqApiConfigurationRecord> recordError({
    required String id,
    required String status,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Groq config $id was not found.');
    }
    final now = DateTime.now().toUtc();
    return update(
      existing.copyWith(
        lastErrorStatus: status,
        lastErrorAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<GroqApiConfigurationRecord> recordTestSuccess(String id) async {
    return recordTestOutcome(
      id: id,
      result: 'working',
      detail: 'Connection test succeeded.',
      clearError: true,
    );
  }

  Future<GroqApiConfigurationRecord> recordTestOutcome({
    required String id,
    required String result,
    String? detail,
    bool clearError = false,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('API configuration $id was not found.');
    }
    final now = DateTime.now().toUtc();
    return update(
      existing.copyWith(
        lastTestedAt: now,
        lastTestResult: result,
        lastTestDetail: detail,
        lastErrorStatus: clearError
            ? null
            : (result == 'working' ? null : result),
        lastErrorAt: clearError || result == 'working' ? null : now,
        updatedAt: now,
        clearLastError: clearError || result == 'working',
      ),
    );
  }
}

class ImportBatchRepository {
  ImportBatchRepository(this._db);

  final AppDatabase _db;

  Future<List<ImportBatchRecord>> listByAccountingDate(
    DateTime accountingDate,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importBatches,
      where: 'accounting_date = ?',
      whereArgs: [encodeDateOnly(accountingDate)],
      orderBy: 'imported_at ASC',
    );
    return rows.map(ImportBatchMapper.fromMap).toList();
  }

  Future<ImportBatchRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importBatches,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ImportBatchMapper.fromMap(rows.first);
  }
}

class ReceiptAuditHistoryRepository {
  ReceiptAuditHistoryRepository(this._db);

  final AppDatabase _db;

  Future<List<ReceiptAuditHistoryRecord>> listForReceipt(
    String receiptId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.receiptAudit,
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'changed_at ASC',
    );
    return rows.map(AuditMapper.fromMap).toList();
  }
}
