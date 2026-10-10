import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ReceiptRepository {
  ReceiptRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<List<ReceiptRecord>> listByAccountingDate(
    DateTime accountingDate, {
    bool includeDeleted = false,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.receipts,
      where: includeDeleted
          ? 'accounting_date = ?'
          : 'accounting_date = ? AND deleted_at IS NULL',
      whereArgs: [encodeDateOnly(accountingDate)],
      orderBy: 'imported_at ASC, created_at ASC',
    );
    return rows.map(ReceiptMapper.fromMap).toList();
  }

  Future<ReceiptRecord?> getById(
    String id, {
    bool includeDeleted = false,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.receipts,
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ReceiptMapper.fromMap(rows.first);
  }

  Future<int> countByAccountingDate(DateTime accountingDate) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.receipts} '
      'WHERE accounting_date = ? AND deleted_at IS NULL',
      [encodeDateOnly(accountingDate)],
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<int> countEnteredByAccountingDate(DateTime accountingDate) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.receipts} '
      'WHERE accounting_date = ? AND deleted_at IS NULL AND entry_status = ?',
      [encodeDateOnly(accountingDate), DbEntryStatus.entered.storageValue],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// Appends receipts for [accountingDate]. Existing rows are never replaced.
  ///
  /// When [existingBatchId] is set, receipts join that batch instead of
  /// creating a new `import_batches` row.
  Future<ImportBatchRecord> appendImport({
    required DateTime accountingDate,
    required List<ReceiptImportDraft> drafts,
    required String source,
    String? notes,
    DateTime? importedAt,
    String? existingBatchId,
  }) async {
    if (drafts.isEmpty) {
      throw ArgumentError('Import drafts must not be empty.');
    }

    final db = await _db.database;
    final now = importedAt?.toUtc() ?? DateTime.now().toUtc();

    late final ImportBatchRecord batch;
    if (existingBatchId != null) {
      final rows = await db.query(
        DbSchema.importBatches,
        where: 'id = ?',
        whereArgs: [existingBatchId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Import batch $existingBatchId was not found.');
      }
      final existing = ImportBatchMapper.fromMap(rows.first);
      batch = existing.copyWith(
        receiptCount: existing.receiptCount + drafts.length,
      );
    } else {
      batch = ImportBatchRecord(
        id: _uuid.v4(),
        accountingDate: dateOnlyUtc(accountingDate),
        importedAt: now,
        source: source,
        receiptCount: drafts.length,
        fileCount: drafts.length,
        notes: notes,
        createdAt: now,
      );
    }

    await db.transaction((txn) async {
      if (existingBatchId == null) {
        await txn.insert(
          DbSchema.importBatches,
          ImportBatchMapper.toMap(batch),
        );
      } else {
        await txn.update(
          DbSchema.importBatches,
          ImportBatchMapper.toMap(batch),
          where: 'id = ?',
          whereArgs: [batch.id],
        );
      }

      for (final draft in drafts) {
        final id = draft.id ?? _uuid.v4();
        final record = ReceiptRecord(
          id: id,
          transactionId: draft.transactionId,
          bankName: draft.bankName,
          bankSenderName: draft.bankSenderName,
          bankReceiverName: draft.bankReceiverName,
          amount: draft.amount,
          currency: draft.currency,
          transactionDateTime: draft.transactionDateTime?.toUtc(),
          accountingDate: dateOnlyUtc(accountingDate),
          importedAt: now,
          whatsappMessageDateTime: draft.whatsappMessageDateTime?.toUtc(),
          whatsappSender: draft.whatsappSender,
          adminMessage: draft.adminMessage,
          originalImagePath: draft.originalImagePath,
          imageHash: draft.imageHash,
          receiptType: draft.receiptType,
          mappedPartyId: draft.mappedPartyId,
          mappedAccountId: draft.mappedAccountId,
          dealerId: draft.dealerId,
          customerId: draft.customerId,
          confidenceScore: draft.confidenceScore,
          reviewStatus: draft.reviewStatus,
          entryStatus: DbEntryStatus.pending,
          notes: draft.notes,
          createdAt: now,
          updatedAt: now,
          importBatchId: batch.id,
        );
        await txn.insert(
          DbSchema.receipts,
          ReceiptMapper.toMap(record),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });

    return batch;
  }

  Future<ReceiptRecord> updateReceipt({
    required ReceiptRecord updated,
    String? changedBy,
    String? reason,
  }) async {
    final db = await _db.database;
    final existing = await getById(updated.id, includeDeleted: true);
    if (existing == null) {
      throw StateError('Receipt ${updated.id} was not found.');
    }
    if (existing.deletedAt != null) {
      throw StateError('Cannot edit a soft-deleted receipt.');
    }

    final now = DateTime.now().toUtc();
    final saved = updated.copyWith(updatedAt: now);
    final audits = _buildAudits(
      existing: existing,
      updated: saved,
      changedAt: now,
      changedBy: changedBy,
      reason: reason,
    );

    await db.transaction((txn) async {
      final count = await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [saved.id],
      );
      if (count != 1) {
        throw StateError('Receipt ${saved.id} was not updated.');
      }
      for (final audit in audits) {
        await txn.insert(DbSchema.receiptAudit, AuditMapper.toMap(audit));
      }
    });

    return saved;
  }

  /// Marks Entered only after manual WinForms typing. Never clears silently.
  Future<ReceiptRecord> markEntered({
    required String id,
    required String enteredBy,
    String? winformsReference,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.hasUnresolvedFinancialConflict) {
      throw StateError(
        'Resolve financial reconciliation before marking Entered.',
      );
    }
    final now = DateTime.now().toUtc();
    return updateReceipt(
      updated: existing.copyWith(
        entryStatus: DbEntryStatus.entered,
        enteredAt: now,
        enteredBy: enteredBy,
        winformsReference: winformsReference ?? existing.winformsReference,
        updatedAt: now,
      ),
      changedBy: enteredBy,
      reason: 'Marked entered for office entry list.',
    );
  }

  /// Undo Entered with an explicit caller confirmation already obtained.
  Future<ReceiptRecord> undoEntered({
    required String id,
    required bool confirmed,
    required String changedBy,
  }) async {
    if (!confirmed) {
      throw StateError('Undo Entered requires confirmation.');
    }
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.entryStatus != DbEntryStatus.entered) {
      return existing;
    }
    return updateReceipt(
      updated: existing.copyWith(
        entryStatus: DbEntryStatus.pending,
        clearEnteredAt: true,
        clearEnteredBy: true,
      ),
      changedBy: changedBy,
      reason: 'Undo Entered after confirmation.',
    );
  }

  Future<List<ReceiptRecord>> markEnteredBulk({
    required List<String> ids,
    required String enteredBy,
  }) async {
    final results = <ReceiptRecord>[];
    for (final id in ids) {
      results.add(await markEntered(id: id, enteredBy: enteredBy));
    }
    return results;
  }

  Future<ReceiptRecord> moveAccountingDate({
    required String id,
    required DateTime newAccountingDate,
    String? changedBy,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.entryStatus == DbEntryStatus.entered) {
      throw StateError(
        'Moving an Entered receipt accounting date requires the '
        'reconciliation workflow (applyFinancialEdit with confirmation).',
      );
    }
    return updateReceipt(
      updated: existing.copyWith(
        accountingDate: dateOnlyUtc(newAccountingDate),
      ),
      changedBy: changedBy,
      reason: 'Moved to another accounting date.',
    );
  }

  /// Atomic financial correction after Entered: receipt + audits + case.
  Future<ReceiptRecord> applyEnteredFinancialCorrection({
    required ReceiptRecord updated,
    required ReconciliationCaseRecord caseRecord,
    String? changedBy,
    String? reason,
  }) async {
    final db = await _db.database;
    final existing = await getById(updated.id, includeDeleted: true);
    if (existing == null) {
      throw StateError('Receipt ${updated.id} was not found.');
    }
    if (existing.deletedAt != null) {
      throw StateError('Cannot edit a soft-deleted receipt.');
    }
    if (existing.entryStatus != DbEntryStatus.entered) {
      throw StateError(
        'Financial correction case requires an Entered receipt.',
      );
    }

    final now = DateTime.now().toUtc();
    final saved = updated.copyWith(
      updatedAt: now,
      entryStatus: DbEntryStatus.entered,
      enteredAt: existing.enteredAt,
      enteredBy: existing.enteredBy,
      reviewStatus: DbReviewStatus.needsReconciliation,
      clearReconciliationCompletedAt: true,
    );
    final audits = _buildAudits(
      existing: existing,
      updated: saved,
      changedAt: now,
      changedBy: changedBy,
      reason: reason,
    );
    final persistedCase = ReconciliationCaseRecord(
      id: caseRecord.id.isEmpty ? _uuid.v4() : caseRecord.id,
      receiptId: saved.id,
      status: ReconciliationCaseStatus.open,
      kind: caseRecord.kind,
      reason: caseRecord.reason,
      correctionNotes: caseRecord.correctionNotes,
      diffs: List.unmodifiable(caseRecord.diffs),
      previousAmount: caseRecord.previousAmount,
      correctedAmount: caseRecord.correctedAmount,
      openedAt: caseRecord.openedAt,
      openedBy: caseRecord.openedBy ?? changedBy,
      createdAt: caseRecord.createdAt,
    );

    await db.transaction((txn) async {
      final count = await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [saved.id],
      );
      if (count != 1) {
        throw StateError('Receipt ${saved.id} was not updated.');
      }
      for (final audit in audits) {
        await txn.insert(DbSchema.receiptAudit, AuditMapper.toMap(audit));
      }
      await txn.insert(
        DbSchema.reconciliationCases,
        ReconciliationCaseMapper.toMap(persistedCase),
      );
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: saved.id,
            fieldName: 'reconciliation_case',
            oldValue: null,
            newValue: persistedCase.id,
            changedAt: now,
            changedBy: changedBy,
            reason: reason,
          ),
        ),
      );
    });

    return saved;
  }

  Future<ReceiptRecord> completeReconciliation({
    required String id,
    required String completedBy,
    String? correctionNotes,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.reviewStatus != DbReviewStatus.needsReconciliation) {
      throw StateError('Receipt $id has no open reconciliation requirement.');
    }

    final now = DateTime.now().toUtc();
    final saved = existing.copyWith(
      reviewStatus: DbReviewStatus.approved,
      entryStatus: DbEntryStatus.entered,
      enteredAt: existing.enteredAt ?? now,
      enteredBy: existing.enteredBy ?? completedBy,
      reconciliationCompletedAt: now,
      updatedAt: now,
    );
    final db = await _db.database;

    await db.transaction((txn) async {
      final count = await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      if (count != 1) {
        throw StateError('Receipt $id was not updated.');
      }

      final openCases = await txn.query(
        DbSchema.reconciliationCases,
        where: 'receipt_id = ? AND status = ?',
        whereArgs: [id, ReconciliationCaseStatus.open.storageValue],
      );
      for (final row in openCases) {
        final open = ReconciliationCaseMapper.fromMap(row);
        final closed = open.copyWith(
          status: ReconciliationCaseStatus.completed,
          completedAt: now,
          completedBy: completedBy,
          correctionNotes: correctionNotes ?? open.correctionNotes,
        );
        await txn.update(
          DbSchema.reconciliationCases,
          ReconciliationCaseMapper.toMap(closed),
          where: 'id = ?',
          whereArgs: [closed.id],
        );
      }

      for (final audit in _buildAudits(
        existing: existing,
        updated: saved,
        changedAt: now,
        changedBy: completedBy,
        reason: 'Office entry correction completed — status Entered.',
      )) {
        await txn.insert(DbSchema.receiptAudit, AuditMapper.toMap(audit));
      }
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: id,
            fieldName: 'reconciliation_completed_at',
            oldValue: existing.reconciliationCompletedAt?.toIso8601String(),
            newValue: encodeDateTime(now),
            changedAt: now,
            changedBy: completedBy,
            reason:
                'Reconciliation completed after manual office entry correction.',
          ),
        ),
      );
    });

    return saved;
  }

  Future<ReceiptRecord> reopenReconciliation({
    required String id,
    required String reopenedBy,
    String? reason,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    final now = DateTime.now().toUtc();
    final saved = existing.copyWith(
      reviewStatus: DbReviewStatus.needsReconciliation,
      entryStatus: DbEntryStatus.entered,
      enteredAt: existing.enteredAt,
      enteredBy: existing.enteredBy,
      clearReconciliationCompletedAt: true,
      updatedAt: now,
    );
    final caseRecord = ReconciliationCaseRecord(
      id: _uuid.v4(),
      receiptId: id,
      status: ReconciliationCaseStatus.open,
      kind: ReconciliationCaseKind.reopen,
      reason:
          reason ??
          'Reconciliation reopened. Office entry may still need review.',
      diffs: const [],
      previousAmount: existing.priorAmount ?? existing.amount,
      correctedAmount: existing.amount,
      openedAt: now,
      openedBy: reopenedBy,
      createdAt: now,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      await txn.insert(
        DbSchema.reconciliationCases,
        ReconciliationCaseMapper.toMap(caseRecord),
      );
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: id,
            fieldName: 'review_status',
            oldValue: existing.reviewStatus.storageValue,
            newValue: saved.reviewStatus.storageValue,
            changedAt: now,
            changedBy: reopenedBy,
            reason: caseRecord.reason,
          ),
        ),
      );
    });
    return saved;
  }

  Future<ReconciliationCaseRecord> addReconciliationCorrectionNotes({
    required String caseId,
    required String notes,
    required String changedBy,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.reconciliationCases,
      where: 'id = ?',
      whereArgs: [caseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Reconciliation case $caseId was not found.');
    }
    final existing = ReconciliationCaseMapper.fromMap(rows.first);
    final merged =
        existing.correctionNotes == null ||
            existing.correctionNotes!.trim().isEmpty
        ? notes
        : '${existing.correctionNotes}\n$notes';
    final updated = existing.copyWith(correctionNotes: merged);
    final now = DateTime.now().toUtc();
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.reconciliationCases,
        ReconciliationCaseMapper.toMap(updated),
        where: 'id = ?',
        whereArgs: [caseId],
      );
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: existing.receiptId,
            fieldName: 'reconciliation_notes',
            oldValue: existing.correctionNotes,
            newValue: merged,
            changedAt: now,
            changedBy: changedBy,
            reason: 'Correction notes added to reconciliation case.',
          ),
        ),
      );
    });
    return updated;
  }

  Future<List<ReconciliationCaseRecord>> listReconciliationCases(
    String receiptId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.reconciliationCases,
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'opened_at ASC, created_at ASC',
    );
    return rows.map(ReconciliationCaseMapper.fromMap).toList();
  }

  Future<List<ReconciliationCaseRecord>> listOpenReconciliationCases({
    DateTime? accountingDate,
  }) async {
    final db = await _db.database;
    if (accountingDate == null) {
      final rows = await db.query(
        DbSchema.reconciliationCases,
        where: 'status = ?',
        whereArgs: [ReconciliationCaseStatus.open.storageValue],
        orderBy: 'opened_at DESC',
      );
      return rows.map(ReconciliationCaseMapper.fromMap).toList();
    }
    final rows = await db.rawQuery(
      '''
SELECT c.*
FROM ${DbSchema.reconciliationCases} c
INNER JOIN ${DbSchema.receipts} r ON r.id = c.receipt_id
WHERE c.status = ?
  AND r.accounting_date = ?
ORDER BY c.opened_at DESC
''',
      [
        ReconciliationCaseStatus.open.storageValue,
        encodeDateOnly(accountingDate),
      ],
    );
    return rows.map(ReconciliationCaseMapper.fromMap).toList();
  }

  Future<({int count, double affectedAmount})> summarizeOpenReconciliation({
    DateTime? accountingDate,
  }) async {
    final cases = await listOpenReconciliationCases(
      accountingDate: accountingDate,
    );
    var amount = 0.0;
    for (final item in cases) {
      amount += (item.correctedAmount ?? item.previousAmount ?? 0).abs();
    }
    return (count: cases.length, affectedAmount: amount);
  }

  Future<ReceiptRecord> softDeleteEnteredWithReconciliationCase({
    required String id,
    required String changedBy,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.entryStatus != DbEntryStatus.entered) {
      return softDelete(id: id, changedBy: changedBy);
    }

    final now = DateTime.now().toUtc();
    final saved = existing.copyWith(
      deletedAt: now,
      updatedAt: now,
      reviewStatus: DbReviewStatus.needsReconciliation,
      entryStatus: DbEntryStatus.entered,
      enteredAt: existing.enteredAt,
      enteredBy: existing.enteredBy,
    );
    final caseRecord = ReconciliationCaseRecord(
      id: _uuid.v4(),
      receiptId: id,
      status: ReconciliationCaseStatus.open,
      kind: ReconciliationCaseKind.deletion,
      reason:
          'Entered receipt deleted. Corresponding office entry may need '
          'reversal.',
      diffs: [
        FinancialFieldDiff(
          field: 'deleted_at',
          label: 'Deleted',
          oldValue: null,
          newValue: encodeDateTime(now),
        ),
      ],
      previousAmount: existing.amount,
      correctedAmount: existing.amount,
      openedAt: now,
      openedBy: changedBy,
      createdAt: now,
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        DbSchema.reconciliationCases,
        ReconciliationCaseMapper.toMap(caseRecord),
      );
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: id,
            fieldName: 'deleted_at',
            oldValue: null,
            newValue: encodeDateTime(now),
            changedAt: now,
            changedBy: changedBy,
            reason: caseRecord.reason,
          ),
        ),
      );
    });
    return saved;
  }

  /// Efficient filtered list. Does not load image bytes — only path metadata.
  Future<List<ReceiptRecord>> listFiltered(ReceiptListFilter filter) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (!filter.includeDeleted) {
      where.add('deleted_at IS NULL');
    }
    if (filter.accountingDate != null) {
      where.add('accounting_date = ?');
      args.add(encodeDateOnly(filter.accountingDate!));
    }
    if (filter.accountingDateFrom != null) {
      where.add('accounting_date >= ?');
      args.add(encodeDateOnly(filter.accountingDateFrom!));
    }
    if (filter.accountingDateTo != null) {
      where.add('accounting_date <= ?');
      args.add(encodeDateOnly(filter.accountingDateTo!));
    }
    if (filter.bankName != null && filter.bankName!.trim().isNotEmpty) {
      where.add('bank_name = ?');
      args.add(filter.bankName!.trim());
    }
    if (filter.mappedAccountId != null) {
      where.add('mapped_account_id = ?');
      args.add(filter.mappedAccountId);
    }
    if (filter.customerId != null) {
      where.add('customer_id = ?');
      args.add(filter.customerId);
    }
    if (filter.dealerId != null) {
      where.add('dealer_id = ?');
      args.add(filter.dealerId);
    }
    if (filter.entryStatus != null) {
      where.add('entry_status = ?');
      args.add(filter.entryStatus!.storageValue);
    }
    if (filter.reviewStatus != null) {
      where.add('review_status = ?');
      args.add(filter.reviewStatus!.storageValue);
    }
    if (filter.searchText != null && filter.searchText!.trim().isNotEmpty) {
      final q = '%${filter.searchText!.trim()}%';
      where.add(
        '(bank_name LIKE ? OR transaction_id LIKE ? OR admin_message LIKE ? '
        'OR bank_sender_name LIKE ? OR bank_receiver_name LIKE ? '
        'OR winforms_reference LIKE ?)',
      );
      args.addAll([q, q, q, q, q, q]);
    }

    final rows = await db.query(
      DbSchema.receipts,
      columns: const [
        'id',
        'transaction_id',
        'bank_name',
        'bank_sender_name',
        'bank_receiver_name',
        'amount',
        'currency',
        'transaction_date_time',
        'accounting_date',
        'imported_at',
        'whatsapp_message_date_time',
        'whatsapp_sender',
        'admin_message',
        'original_image_path',
        'image_hash',
        'receipt_type',
        'mapped_party_id',
        'mapped_account_id',
        'dealer_id',
        'customer_id',
        'confidence_score',
        'review_status',
        'entry_status',
        'entered_at',
        'entered_by',
        'winforms_reference',
        'prior_amount',
        'prior_party_name',
        'prior_account_id',
        'reconciliation_completed_at',
        'notes',
        'created_at',
        'updated_at',
        'deleted_at',
        'import_batch_id',
      ],
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'accounting_date DESC, imported_at ASC, created_at ASC',
      limit: filter.limit,
      offset: filter.offset,
    );
    return rows.map(ReceiptMapper.fromMap).toList();
  }

  /// Aggregate day metrics without loading receipt images.
  Future<DailyDeskSummary> summarizeAccountingDate(
    DateTime accountingDate,
  ) async {
    final db = await _db.database;
    final date = encodeDateOnly(accountingDate);
    final totals = await db.rawQuery(
      '''
SELECT
  COUNT(*) AS total_count,
  COALESCE(SUM(CASE WHEN receipt_type = 'sent' THEN amount ELSE 0 END), 0)
    AS total_sent,
  COALESCE(SUM(CASE WHEN receipt_type != 'sent' THEN amount ELSE 0 END), 0)
    AS total_received,
  COALESCE(SUM(CASE WHEN entry_status = 'pending'
    AND review_status != 'needs_reconciliation' THEN 1 ELSE 0 END), 0)
    AS pending_count,
  COALESCE(SUM(CASE WHEN entry_status = 'entered'
    AND review_status != 'needs_reconciliation' THEN 1 ELSE 0 END), 0)
    AS entered_count,
  COALESCE(SUM(CASE WHEN review_status = 'needs_reconciliation'
    THEN 1 ELSE 0 END), 0) AS reconciliation_count
FROM ${DbSchema.receipts}
WHERE accounting_date = ? AND deleted_at IS NULL
''',
      [date],
    );
    final row = totals.first;
    final byAccount = await db.rawQuery(
      '''
SELECT mapped_account_id AS account_id,
  COUNT(*) AS c,
  COALESCE(SUM(CASE WHEN receipt_type = 'sent' THEN amount ELSE 0 END), 0)
    AS sent,
  COALESCE(SUM(CASE WHEN receipt_type != 'sent' THEN amount ELSE 0 END), 0)
    AS received
FROM ${DbSchema.receipts}
WHERE accounting_date = ? AND deleted_at IS NULL
GROUP BY mapped_account_id
''',
      [date],
    );
    final countBy = <String, int>{};
    final receivedBy = <String, double>{};
    final sentBy = <String, double>{};
    for (final accountRow in byAccount) {
      final id = accountRow['account_id'] as String?;
      if (id == null) {
        continue;
      }
      countBy[id] = (accountRow['c'] as num).toInt();
      receivedBy[id] = (accountRow['received'] as num).toDouble();
      sentBy[id] = (accountRow['sent'] as num).toDouble();
    }
    return DailyDeskSummary(
      accountingDate: dateOnlyUtc(accountingDate),
      totalCount: (row['total_count'] as num).toInt(),
      totalReceived: (row['total_received'] as num).toDouble(),
      totalSent: (row['total_sent'] as num).toDouble(),
      pendingCount: (row['pending_count'] as num).toInt(),
      enteredCount: (row['entered_count'] as num).toInt(),
      reconciliationCount: (row['reconciliation_count'] as num).toInt(),
      countByAccountId: countBy,
      receivedByAccountId: receivedBy,
      sentByAccountId: sentBy,
    );
  }

  Future<Map<DateTime, int>> countByAccountingDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
SELECT accounting_date, COUNT(*) AS c
FROM ${DbSchema.receipts}
WHERE deleted_at IS NULL
  AND accounting_date >= ?
  AND accounting_date <= ?
GROUP BY accounting_date
''',
      [encodeDateOnly(from), encodeDateOnly(to)],
    );
    return {
      for (final row in rows)
        decodeDateOnly(row['accounting_date']! as String): (row['c'] as num)
            .toInt(),
    };
  }

  Future<ReceiptRecord> softDelete({
    required String id,
    String? changedBy,
    String? reason,
    bool allowEnteredWithoutReconciliation = false,
  }) async {
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.entryStatus == DbEntryStatus.entered &&
        !allowEnteredWithoutReconciliation &&
        !existing.hasUnresolvedFinancialConflict) {
      throw StateError(
        'Entered receipts require reconciliation review before delete '
        '(office entry may still exist).',
      );
    }
    final now = DateTime.now().toUtc();
    final saved = existing.copyWith(
      deletedAt: now,
      updatedAt: now,
      reviewStatus: existing.entryStatus == DbEntryStatus.entered
          ? DbReviewStatus.needsReconciliation
          : existing.reviewStatus,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: id,
            fieldName: 'deleted_at',
            oldValue: null,
            newValue: encodeDateTime(now),
            changedAt: now,
            changedBy: changedBy,
            reason: reason ?? 'Soft deleted',
          ),
        ),
      );
    });
    return saved;
  }

  Future<ReceiptRecord> restore({
    required String id,
    String? changedBy,
    String? reason,
  }) async {
    final existing = await getById(id, includeDeleted: true);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    if (existing.deletedAt == null) {
      return existing;
    }
    final now = DateTime.now().toUtc();
    // Never silently clear reconciliation when restoring an Entered receipt.
    final saved = existing.copyWith(
      clearDeletedAt: true,
      updatedAt: now,
      reviewStatus: existing.entryStatus == DbEntryStatus.entered
          ? DbReviewStatus.needsReconciliation
          : existing.reviewStatus,
      entryStatus: existing.entryStatus,
      enteredAt: existing.enteredAt,
      enteredBy: existing.enteredBy,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        DbSchema.receipts,
        ReceiptMapper.toMap(saved),
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert(
        DbSchema.receiptAudit,
        AuditMapper.toMap(
          ReceiptAuditHistoryRecord(
            id: _uuid.v4(),
            receiptId: id,
            fieldName: 'deleted_at',
            oldValue: encodeDateTime(existing.deletedAt!),
            newValue: null,
            changedAt: now,
            changedBy: changedBy,
            reason:
                reason ??
                (existing.entryStatus == DbEntryStatus.entered
                    ? 'Restored Entered receipt; reconciliation still required.'
                    : 'Restored from soft delete'),
          ),
        ),
      );
    });
    return saved;
  }

  /// Permanent delete requires [confirmPermanentDelete] = true.
  Future<void> permanentlyDelete({
    required String id,
    required bool confirmPermanentDelete,
    String? changedBy,
  }) async {
    if (!confirmPermanentDelete) {
      throw StateError('Permanent delete requires explicit confirmation.');
    }
    final existing = await getById(id, includeDeleted: true);
    if (existing == null) {
      throw StateError('Receipt $id was not found.');
    }
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        DbSchema.reconciliationCases,
        where: 'receipt_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        DbSchema.receiptAudit,
        where: 'receipt_id = ?',
        whereArgs: [id],
      );
      final count = await txn.delete(
        DbSchema.receipts,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) {
        throw StateError('Receipt $id was not permanently deleted.');
      }
    });
  }

  Future<List<ReceiptAuditHistoryRecord>> listAuditHistory(
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

  /// Finds possible duplicates. Never deletes matching receipts.
  Future<List<DuplicateMatch>> findPossibleDuplicates(
    ReceiptImportDraft draft, {
    DateTime? accountingDate,
  }) async {
    final db = await _db.database;
    final parts = <String>[];
    final args = <Object?>[];

    if (draft.transactionId != null && draft.transactionId!.isNotEmpty) {
      parts.add('transaction_id = ?');
      args.add(draft.transactionId);
    }
    if (draft.imageHash != null && draft.imageHash!.isNotEmpty) {
      parts.add('image_hash = ?');
      args.add(draft.imageHash);
    }

    final date = encodeDateOnly(
      accountingDate ?? draft.transactionDateTime ?? DateTime.now().toUtc(),
    );
    parts.add(
      '(bank_name = ? AND ABS(amount - ?) < 0.0001 AND accounting_date = ?)',
    );
    args.addAll([draft.bankName, draft.amount, date]);

    if (draft.transactionDateTime != null) {
      parts.add(
        '(bank_name = ? AND ABS(amount - ?) < 0.0001 AND transaction_date_time = ?)',
      );
      args.addAll([
        draft.bankName,
        draft.amount,
        encodeDateTime(draft.transactionDateTime!.toUtc()),
      ]);
    }

    final rows = await db.query(
      DbSchema.receipts,
      where: 'deleted_at IS NULL AND (${parts.join(' OR ')})',
      whereArgs: args,
    );

    return [
      for (final row in rows)
        DuplicateMatch(
          existing: ReceiptMapper.fromMap(row),
          reasons: _duplicateReasons(draft, ReceiptMapper.fromMap(row)),
        ),
    ];
  }

  List<String> _duplicateReasons(
    ReceiptImportDraft draft,
    ReceiptRecord existing,
  ) {
    final reasons = <String>[];
    if (draft.transactionId != null &&
        draft.transactionId!.isNotEmpty &&
        draft.transactionId == existing.transactionId) {
      reasons.add('transaction_id');
    }
    if (draft.imageHash != null &&
        draft.imageHash!.isNotEmpty &&
        draft.imageHash == existing.imageHash) {
      reasons.add('image_hash');
    }
    if (draft.bankName == existing.bankName &&
        (draft.amount - existing.amount).abs() < 0.0001) {
      reasons.add('bank_amount');
    }
    if (draft.transactionDateTime != null &&
        existing.transactionDateTime != null &&
        draft.transactionDateTime!.toUtc() ==
            existing.transactionDateTime!.toUtc()) {
      reasons.add('transaction_date_time');
    }
    return reasons;
  }

  List<ReceiptAuditHistoryRecord> _buildAudits({
    required ReceiptRecord existing,
    required ReceiptRecord updated,
    required DateTime changedAt,
    String? changedBy,
    String? reason,
  }) {
    final audits = <ReceiptAuditHistoryRecord>[];

    void track(String field, Object? oldValue, Object? newValue) {
      final oldText = oldValue?.toString();
      final newText = newValue?.toString();
      if (oldText == newText) {
        return;
      }
      audits.add(
        ReceiptAuditHistoryRecord(
          id: _uuid.v4(),
          receiptId: existing.id,
          fieldName: field,
          oldValue: oldText,
          newValue: newText,
          changedAt: changedAt,
          changedBy: changedBy,
          reason: reason,
        ),
      );
    }

    track('amount', existing.amount, updated.amount);
    track(
      'receipt_type',
      existing.receiptType.storageValue,
      updated.receiptType.storageValue,
    );
    track('mapped_party_id', existing.mappedPartyId, updated.mappedPartyId);
    track('customer_id', existing.customerId, updated.customerId);
    track('dealer_id', existing.dealerId, updated.dealerId);
    track(
      'mapped_account_id',
      existing.mappedAccountId,
      updated.mappedAccountId,
    );
    track('transaction_id', existing.transactionId, updated.transactionId);
    track(
      'accounting_date',
      encodeDateOnly(existing.accountingDate),
      encodeDateOnly(updated.accountingDate),
    );
    track(
      'transaction_date_time',
      existing.transactionDateTime == null
          ? null
          : encodeDateTime(existing.transactionDateTime!),
      updated.transactionDateTime == null
          ? null
          : encodeDateTime(updated.transactionDateTime!),
    );
    track('notes', existing.notes, updated.notes);
    track(
      'entry_status',
      existing.entryStatus.storageValue,
      updated.entryStatus.storageValue,
    );
    track(
      'review_status',
      existing.reviewStatus.storageValue,
      updated.reviewStatus.storageValue,
    );
    track('admin_message', existing.adminMessage, updated.adminMessage);
    track(
      'winforms_reference',
      existing.winformsReference,
      updated.winformsReference,
    );
    track('entered_at', existing.enteredAt, updated.enteredAt);
    track('entered_by', existing.enteredBy, updated.enteredBy);
    track('prior_amount', existing.priorAmount, updated.priorAmount);
    track(
      'reconciliation_completed_at',
      existing.reconciliationCompletedAt == null
          ? null
          : encodeDateTime(existing.reconciliationCompletedAt!),
      updated.reconciliationCompletedAt == null
          ? null
          : encodeDateTime(updated.reconciliationCompletedAt!),
    );

    return audits;
  }
}
