import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/database/office_mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/utils/alias_normalize.dart';
import 'package:uuid/uuid.dart';

class CustomerRepository {
  CustomerRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<CustomerRecord>> list({
    bool includeArchived = false,
    String? search,
  }) async {
    final db = await _db.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeArchived) {
      clauses.add('deleted_at IS NULL');
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim().toLowerCase()}%';
      clauses.add(
        '(LOWER(name) LIKE ? OR id IN ('
        'SELECT customer_id FROM ${DbSchema.customerAliases} '
        'WHERE LOWER(alias_name) LIKE ? OR normalized_alias LIKE ?))',
      );
      args.addAll([q, q, '%${normalizeAlias(search)}%']);
    }
    final rows = await db.query(
      DbSchema.customers,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(CustomerMapper.fromMap).toList();
  }

  Future<CustomerRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.customers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CustomerMapper.fromMap(rows.first);
  }

  Future<CustomerRecord> create({
    required String name,
    String? usualAccountId,
    String? notes,
    List<String> aliases = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final record = CustomerRecord(
      id: _uuid.v4(),
      name: name.trim(),
      usualAccountId: usualAccountId,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(DbSchema.customers, CustomerMapper.toMap(record));
      for (final alias in aliases) {
        final trimmed = alias.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        await txn.insert(
          DbSchema.customerAliases,
          PartyAliasMapper.toCustomerMap(
            PartyAliasRecord(
              id: _uuid.v4(),
              ownerKind: PartyAliasOwnerKind.customer,
              ownerId: record.id,
              aliasName: trimmed,
              normalizedAlias: normalizeAlias(trimmed),
              approvalStatus: AliasApprovalStatus.approved,
              createdAt: now,
            ),
          ),
        );
      }
    });
    return record;
  }

  Future<CustomerRecord> update(CustomerRecord record) async {
    final now = DateTime.now().toUtc();
    final saved = CustomerRecord(
      id: record.id,
      name: record.name.trim(),
      usualAccountId: record.usualAccountId,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: now,
      deletedAt: record.deletedAt,
    );
    final db = await _db.database;
    await db.update(
      DbSchema.customers,
      CustomerMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [saved.id],
    );
    return saved;
  }

  Future<void> archive(String id) async {
    final db = await _db.database;
    await db.update(
      DbSchema.customers,
      {
        'deleted_at': encodeDateTime(DateTime.now().toUtc()),
        'updated_at': encodeDateTime(DateTime.now().toUtc()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restore(String id) async {
    final db = await _db.database;
    await db.update(
      DbSchema.customers,
      {
        'deleted_at': null,
        'updated_at': encodeDateTime(DateTime.now().toUtc()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PartyAliasRecord>> listAliases(String customerId) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.customerAliases,
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PartyAliasMapper.fromCustomerMap).toList();
  }

  Future<PartyAliasRecord> addAlias({
    required String customerId,
    required String aliasName,
    AliasApprovalStatus approvalStatus = AliasApprovalStatus.pending,
  }) async {
    final trimmed = aliasName.trim();
    final record = PartyAliasRecord(
      id: _uuid.v4(),
      ownerKind: PartyAliasOwnerKind.customer,
      ownerId: customerId,
      aliasName: trimmed,
      normalizedAlias: normalizeAlias(trimmed),
      approvalStatus: approvalStatus,
      createdAt: DateTime.now().toUtc(),
    );
    final db = await _db.database;
    await db.insert(
      DbSchema.customerAliases,
      PartyAliasMapper.toCustomerMap(record),
    );
    return record;
  }

  Future<void> approveAlias(String aliasId) async {
    final db = await _db.database;
    await db.update(
      DbSchema.customerAliases,
      {'approval_status': AliasApprovalStatus.approved.storageValue},
      where: 'id = ?',
      whereArgs: [aliasId],
    );
  }

  Future<List<Map<String, Object?>>> listReceiptHistory(
    String customerId, {
    int limit = 100,
  }) async {
    final db = await _db.database;
    return db.query(
      DbSchema.receipts,
      where: 'customer_id = ? AND deleted_at IS NULL',
      whereArgs: [customerId],
      orderBy: 'accounting_date DESC',
      limit: limit,
    );
  }
}

class DealerRepository {
  DealerRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<DealerRecord>> list({
    bool includeArchived = false,
    String? search,
  }) async {
    final db = await _db.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeArchived) {
      clauses.add('deleted_at IS NULL');
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim().toLowerCase()}%';
      clauses.add(
        '(LOWER(name) LIKE ? OR id IN ('
        'SELECT dealer_id FROM ${DbSchema.dealerAliases} '
        'WHERE LOWER(alias_name) LIKE ? OR normalized_alias LIKE ?))',
      );
      args.addAll([q, q, '%${normalizeAlias(search)}%']);
    }
    final rows = await db.query(
      DbSchema.dealers,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(DealerMapper.fromMap).toList();
  }

  Future<DealerRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.dealers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DealerMapper.fromMap(rows.first);
  }

  Future<DealerRecord> create({
    required String name,
    String? usualAccountId,
    String? notes,
    List<String> aliases = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final record = DealerRecord(
      id: _uuid.v4(),
      name: name.trim(),
      usualAccountId: usualAccountId,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(DbSchema.dealers, DealerMapper.toMap(record));
      for (final alias in aliases) {
        final trimmed = alias.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        await txn.insert(
          DbSchema.dealerAliases,
          PartyAliasMapper.toDealerMap(
            PartyAliasRecord(
              id: _uuid.v4(),
              ownerKind: PartyAliasOwnerKind.dealer,
              ownerId: record.id,
              aliasName: trimmed,
              normalizedAlias: normalizeAlias(trimmed),
              approvalStatus: AliasApprovalStatus.approved,
              createdAt: now,
            ),
          ),
        );
      }
    });
    return record;
  }

  Future<DealerRecord> update(DealerRecord record) async {
    final now = DateTime.now().toUtc();
    final saved = DealerRecord(
      id: record.id,
      name: record.name.trim(),
      usualAccountId: record.usualAccountId,
      notes: record.notes,
      createdAt: record.createdAt,
      updatedAt: now,
      deletedAt: record.deletedAt,
    );
    final db = await _db.database;
    await db.update(
      DbSchema.dealers,
      DealerMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [saved.id],
    );
    return saved;
  }

  Future<void> archive(String id) async {
    final db = await _db.database;
    await db.update(
      DbSchema.dealers,
      {
        'deleted_at': encodeDateTime(DateTime.now().toUtc()),
        'updated_at': encodeDateTime(DateTime.now().toUtc()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restore(String id) async {
    final db = await _db.database;
    await db.update(
      DbSchema.dealers,
      {
        'deleted_at': null,
        'updated_at': encodeDateTime(DateTime.now().toUtc()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PartyAliasRecord>> listAliases(String dealerId) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.dealerAliases,
      where: 'dealer_id = ?',
      whereArgs: [dealerId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PartyAliasMapper.fromDealerMap).toList();
  }

  Future<PartyAliasRecord> addAlias({
    required String dealerId,
    required String aliasName,
    AliasApprovalStatus approvalStatus = AliasApprovalStatus.pending,
  }) async {
    final trimmed = aliasName.trim();
    final record = PartyAliasRecord(
      id: _uuid.v4(),
      ownerKind: PartyAliasOwnerKind.dealer,
      ownerId: dealerId,
      aliasName: trimmed,
      normalizedAlias: normalizeAlias(trimmed),
      approvalStatus: approvalStatus,
      createdAt: DateTime.now().toUtc(),
    );
    final db = await _db.database;
    await db.insert(
      DbSchema.dealerAliases,
      PartyAliasMapper.toDealerMap(record),
    );
    return record;
  }

  Future<void> approveAlias(String aliasId) async {
    final db = await _db.database;
    await db.update(
      DbSchema.dealerAliases,
      {'approval_status': AliasApprovalStatus.approved.storageValue},
      where: 'id = ?',
      whereArgs: [aliasId],
    );
  }

  Future<List<Map<String, Object?>>> listReceiptHistory(
    String dealerId, {
    int limit = 100,
  }) async {
    final db = await _db.database;
    return db.query(
      DbSchema.receipts,
      where: 'dealer_id = ? AND deleted_at IS NULL',
      whereArgs: [dealerId],
      orderBy: 'accounting_date DESC',
      limit: limit,
    );
  }
}
