import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/office_mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/utils/alias_normalize.dart';
import 'package:uuid/uuid.dart';

class OfficeAccountRepository {
  OfficeAccountRepository(this._db, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<OfficeAccountRecord>> list({
    bool includeArchived = true,
    bool includeInactive = true,
    bool includeDeleted = false,
    String? search,
  }) async {
    final db = await _db.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) {
      clauses.add('deleted_at IS NULL');
    }
    if (!includeArchived) {
      clauses.add("status != 'archived'");
    }
    if (!includeInactive) {
      clauses.add("status != 'inactive'");
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim().toLowerCase()}%';
      clauses.add(
        '(LOWER(display_name) LIKE ? OR LOWER(short_name) LIKE ? OR id IN ('
        'SELECT office_account_id FROM ${DbSchema.officeAccountAliases} '
        'WHERE LOWER(alias_name) LIKE ? OR normalized_alias LIKE ?))',
      );
      final normalized = '%${normalizeAlias(search)}%';
      args.addAll([q, q, q, normalized]);
    }
    final rows = await db.query(
      DbSchema.accountMappings,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
    return rows.map(OfficeAccountMapper.fromMap).toList();
  }

  Future<List<OfficeAccountRecord>> listSelectableForNewEntries() {
    return list(includeArchived: false, includeInactive: false);
  }

  Future<OfficeAccountRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.accountMappings,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return OfficeAccountMapper.fromMap(rows.first);
  }

  Future<OfficeAccountRecord> create({
    required String displayName,
    String? bankAlias,
    String? notes,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Display name is required.');
    }
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final record = OfficeAccountRecord(
      id: id,
      displayName: name,
      status: OfficeAccountStatus.active,
      officeKey: 'acct_$id',
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(
        DbSchema.accountMappings,
        OfficeAccountMapper.toMap(record),
      );
      final alias = (bankAlias ?? '').trim();
      if (alias.isNotEmpty) {
        await txn.insert(
          DbSchema.officeAccountAliases,
          OfficeAliasMapper.toMap(
            OfficeAccountAliasRecord(
              id: _uuid.v4(),
              officeAccountId: id,
              aliasName: alias,
              normalizedAlias: normalizeAlias(alias),
              approvalStatus: AliasApprovalStatus.approved,
              createdAt: now,
            ),
          ),
        );
      }
    });
    return record;
  }

  Future<OfficeAccountRecord> rename({
    required String id,
    required String displayName,
  }) async {
    final existing = await getById(id);
    if (existing == null || existing.deletedAt != null) {
      throw StateError('Office account was not found.');
    }
    final name = displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Display name is required.');
    }
    final saved = existing.copyWith(
      displayName: name,
      updatedAt: DateTime.now().toUtc(),
    );
    final db = await _db.database;
    await db.update(
      DbSchema.accountMappings,
      OfficeAccountMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [id],
    );
    return saved;
  }

  Future<OfficeAccountRecord> setStatus({
    required String id,
    required OfficeAccountStatus status,
  }) async {
    final existing = await getById(id);
    if (existing == null || existing.deletedAt != null) {
      throw StateError('Office account was not found.');
    }
    final now = DateTime.now().toUtc();
    final saved = existing.copyWith(
      status: status,
      updatedAt: now,
      archivedAt: status == OfficeAccountStatus.archived ? now : null,
      clearArchivedAt: status != OfficeAccountStatus.archived,
    );
    final db = await _db.database;
    await db.update(
      DbSchema.accountMappings,
      OfficeAccountMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [id],
    );
    return saved;
  }

  Future<OfficeAccountRecord> archive(String id) =>
      setStatus(id: id, status: OfficeAccountStatus.archived);

  Future<OfficeAccountRecord> restore(String id) =>
      setStatus(id: id, status: OfficeAccountStatus.active);

  Future<OfficeAccountRecord> deactivate(String id) =>
      setStatus(id: id, status: OfficeAccountStatus.inactive);

  Future<OfficeAccountRecord> activate(String id) =>
      setStatus(id: id, status: OfficeAccountStatus.active);

  Future<int> countLinkedReceipts(String accountId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.receipts} '
      'WHERE mapped_account_id = ?',
      [accountId],
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<int> countLinkedParties(String accountId) async {
    final db = await _db.database;
    final customers = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.customers} WHERE usual_account_id = ?',
      [accountId],
    );
    final dealers = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.dealers} WHERE usual_account_id = ?',
      [accountId],
    );
    return (customers.first['c'] as num).toInt() +
        (dealers.first['c'] as num).toInt();
  }

  /// Permanent delete only when nothing references the account.
  Future<void> permanentlyDelete({
    required String id,
    required bool confirmPermanentDelete,
  }) async {
    if (!confirmPermanentDelete) {
      throw StateError('Permanent delete requires explicit confirmation.');
    }
    final linkedReceipts = await countLinkedReceipts(id);
    final linkedParties = await countLinkedParties(id);
    if (linkedReceipts > 0 || linkedParties > 0) {
      throw StateError(
        'This office account still has linked receipts or parties. '
        'Archive it instead of deleting.',
      );
    }
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        DbSchema.officeAccountAliases,
        where: 'office_account_id = ?',
        whereArgs: [id],
      );
      final count = await txn.delete(
        DbSchema.accountMappings,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) {
        throw StateError('Office account was not deleted.');
      }
    });
  }

  Future<List<OfficeAccountAliasRecord>> listAliases(String accountId) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.officeAccountAliases,
      where: 'office_account_id = ?',
      whereArgs: [accountId],
      orderBy: 'created_at ASC',
    );
    return rows.map(OfficeAliasMapper.fromMap).toList();
  }

  Future<OfficeAccountAliasRecord> addAlias({
    required String accountId,
    required String aliasName,
    AliasApprovalStatus approvalStatus = AliasApprovalStatus.approved,
  }) async {
    final alias = aliasName.trim();
    if (alias.isEmpty) {
      throw ArgumentError('Alias name is required.');
    }
    final account = await getById(accountId);
    if (account == null || account.deletedAt != null) {
      throw StateError('Office account was not found.');
    }
    final record = OfficeAccountAliasRecord(
      id: _uuid.v4(),
      officeAccountId: accountId,
      aliasName: alias,
      normalizedAlias: normalizeAlias(alias),
      approvalStatus: approvalStatus,
      createdAt: DateTime.now().toUtc(),
    );
    final db = await _db.database;
    await db.insert(
      DbSchema.officeAccountAliases,
      OfficeAliasMapper.toMap(record),
    );
    return record;
  }

  Future<void> removeAlias(String aliasId) async {
    final db = await _db.database;
    await db.delete(
      DbSchema.officeAccountAliases,
      where: 'id = ?',
      whereArgs: [aliasId],
    );
  }

  Future<OfficeAccountAliasRecord> setAliasApproval({
    required String aliasId,
    required AliasApprovalStatus status,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.officeAccountAliases,
      where: 'id = ?',
      whereArgs: [aliasId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Alias was not found.');
    }
    final current = OfficeAliasMapper.fromMap(rows.first);
    final saved = OfficeAccountAliasRecord(
      id: current.id,
      officeAccountId: current.officeAccountId,
      aliasName: current.aliasName,
      normalizedAlias: current.normalizedAlias,
      approvalStatus: status,
      createdAt: current.createdAt,
    );
    await db.update(
      DbSchema.officeAccountAliases,
      OfficeAliasMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [aliasId],
    );
    return saved;
  }

  Future<List<Map<String, Object?>>> listLinkedReceiptRows(
    String accountId, {
    int limit = 100,
  }) async {
    final db = await _db.database;
    return db.query(
      DbSchema.receipts,
      where: 'mapped_account_id = ? AND deleted_at IS NULL',
      whereArgs: [accountId],
      orderBy: 'accounting_date DESC, imported_at DESC',
      limit: limit,
    );
  }
}

/// Backward-compatible name used by older imports.
typedef AccountMappingRepository = OfficeAccountRepository;
