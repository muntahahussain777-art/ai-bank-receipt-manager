import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:uuid/uuid.dart';

class ImportQueueRepository {
  ImportQueueRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<ImportBatchRecord> createBatch({
    required DateTime accountingDate,
    required String source,
    required int fileCount,
    String? notes,
    DateTime? importedAt,
  }) async {
    final now = importedAt?.toUtc() ?? DateTime.now().toUtc();
    final record = ImportBatchRecord(
      id: _uuid.v4(),
      accountingDate: dateOnlyUtc(accountingDate),
      importedAt: now,
      source: source,
      receiptCount: 0,
      fileCount: fileCount,
      batchStatus: ImportBatchStatus.open,
      notes: notes,
      createdAt: now,
    );
    final db = await _db.database;
    await db.insert(DbSchema.importBatches, ImportBatchMapper.toMap(record));
    return record;
  }

  Future<ImportBatchRecord?> getBatch(String id) async {
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

  Future<List<ImportBatchRecord>> listRecentBatches({int limit = 30}) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importBatches,
      orderBy: 'imported_at DESC',
      limit: limit,
    );
    return rows.map(ImportBatchMapper.fromMap).toList();
  }

  Future<ImportBatchRecord> updateBatch(ImportBatchRecord batch) async {
    final db = await _db.database;
    await db.update(
      DbSchema.importBatches,
      ImportBatchMapper.toMap(batch),
      where: 'id = ?',
      whereArgs: [batch.id],
    );
    return batch;
  }

  Future<ImportQueueItemRecord> enqueue({
    required String batchId,
    required String sourceKind,
    required String storedPath,
    String? groupId,
    String? originalUri,
    String? imageHash,
    String? mimeType,
    String? displayName,
    String? adminNoteOverride,
  }) async {
    final now = DateTime.now().toUtc();
    final record = ImportQueueItemRecord(
      id: _uuid.v4(),
      batchId: batchId,
      groupId: groupId,
      sourceKind: sourceKind,
      originalUri: originalUri,
      storedPath: storedPath,
      imageHash: imageHash,
      mimeType: mimeType,
      displayName: displayName,
      queueStatus: ImportQueueStatus.queued,
      adminNoteOverride: adminNoteOverride,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db.database;
    await db.insert(DbSchema.importQueueItems, ImportQueueItemMapper.toMap(record));
    return record;
  }

  Future<ImportQueueItemRecord> updateItem(ImportQueueItemRecord item) async {
    final saved = ImportQueueItemRecord(
      id: item.id,
      batchId: item.batchId,
      groupId: item.groupId,
      sourceKind: item.sourceKind,
      originalUri: item.originalUri,
      storedPath: item.storedPath,
      imageHash: item.imageHash,
      mimeType: item.mimeType,
      displayName: item.displayName,
      queueStatus: item.queueStatus,
      errorMessage: item.errorMessage,
      extractionId: item.extractionId,
      receiptId: item.receiptId,
      duplicateOfReceiptId: item.duplicateOfReceiptId,
      adminNoteOverride: item.adminNoteOverride,
      retryCount: item.retryCount,
      createdAt: item.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    final db = await _db.database;
    await db.update(
      DbSchema.importQueueItems,
      ImportQueueItemMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [saved.id],
    );
    return saved;
  }

  Future<ImportQueueItemRecord?> getItem(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importQueueItems,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ImportQueueItemMapper.fromMap(rows.first);
  }

  Future<List<ImportQueueItemRecord>> listForBatch(String batchId) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importQueueItems,
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ImportQueueItemMapper.fromMap).toList();
  }

  Future<List<ImportQueueItemRecord>> listByStatus(
    ImportQueueStatus status, {
    int limit = 100,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importQueueItems,
      where: 'queue_status = ?',
      whereArgs: [status.storageValue],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(ImportQueueItemMapper.fromMap).toList();
  }

  Future<List<ImportQueueItemRecord>> listRetryable({int limit = 100}) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.importQueueItems,
      where: "queue_status IN ('failed', 'queued')",
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(ImportQueueItemMapper.fromMap).toList();
  }

  Future<void> assignGroup({
    required List<String> itemIds,
    required String groupId,
  }) async {
    if (itemIds.isEmpty) {
      return;
    }
    final db = await _db.database;
    final now = encodeDateTime(DateTime.now().toUtc());
    for (final id in itemIds) {
      await db.update(
        DbSchema.importQueueItems,
        {'group_id': groupId, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<ImportBatchRecord> refreshBatchCounts(String batchId) async {
    final items = await listForBatch(batchId);
    final batch = await getBatch(batchId);
    if (batch == null) {
      throw StateError('Batch $batchId was not found.');
    }
    var success = 0;
    var failed = 0;
    var duplicates = 0;
    var pendingReview = 0;
    var receipts = 0;
    for (final item in items) {
      switch (item.queueStatus) {
        case ImportQueueStatus.succeeded:
          success++;
          receipts++;
        case ImportQueueStatus.failed:
          failed++;
        case ImportQueueStatus.skippedDuplicate:
          duplicates++;
        case ImportQueueStatus.awaitingReview:
        case ImportQueueStatus.processing:
        case ImportQueueStatus.queued:
          pendingReview++;
        case ImportQueueStatus.cancelled:
          break;
      }
    }
    final allTerminal = items.every(
      (item) =>
          item.queueStatus == ImportQueueStatus.succeeded ||
          item.queueStatus == ImportQueueStatus.failed ||
          item.queueStatus == ImportQueueStatus.skippedDuplicate ||
          item.queueStatus == ImportQueueStatus.cancelled,
    );
    return updateBatch(
      batch.copyWith(
        successCount: success,
        failedCount: failed,
        duplicateCount: duplicates,
        pendingReviewCount: pendingReview,
        receiptCount: receipts,
        fileCount: items.length,
        batchStatus: allTerminal && items.isNotEmpty
            ? ImportBatchStatus.completed
            : ImportBatchStatus.processing,
      ),
    );
  }
}
