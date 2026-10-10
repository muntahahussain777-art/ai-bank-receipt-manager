import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:uuid/uuid.dart';

class AiExtractionRepository {
  AiExtractionRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Future<AiExtractionRecord> insert(AiExtractionRecord record) async {
    final db = await _db.database;
    await db.insert(DbSchema.aiExtractions, AiExtractionMapper.toMap(record));
    return record;
  }

  Future<AiExtractionRecord> create({
    String? receiptId,
    required String imagePath,
    String? imageHash,
    String? rawAiJson,
    String? rawParseStatus,
    required AiProcessingStatus processingStatus,
    String? errorCode,
    String? errorMessage,
    String? modelUsed,
    String? keyConfigId,
    String? proposedJson,
    String? userCorrectedJson,
    bool appliedToReceipt = false,
    required bool authorizationGranted,
  }) async {
    final now = DateTime.now().toUtc();
    final record = AiExtractionRecord(
      id: _uuid.v4(),
      receiptId: receiptId,
      imagePath: imagePath,
      imageHash: imageHash,
      rawAiJson: rawAiJson,
      rawParseStatus: rawParseStatus,
      processingStatus: processingStatus,
      errorCode: errorCode,
      errorMessage: errorMessage,
      modelUsed: modelUsed,
      keyConfigId: keyConfigId,
      proposedJson: proposedJson,
      userCorrectedJson: userCorrectedJson,
      appliedToReceipt: appliedToReceipt,
      authorizationGranted: authorizationGranted,
      createdAt: now,
      updatedAt: now,
    );
    return insert(record);
  }

  Future<AiExtractionRecord> update(AiExtractionRecord record) async {
    final saved = AiExtractionRecord(
      id: record.id,
      receiptId: record.receiptId,
      imagePath: record.imagePath,
      imageHash: record.imageHash,
      rawAiJson: record.rawAiJson,
      rawParseStatus: record.rawParseStatus,
      processingStatus: record.processingStatus,
      errorCode: record.errorCode,
      errorMessage: record.errorMessage,
      modelUsed: record.modelUsed,
      keyConfigId: record.keyConfigId,
      proposedJson: record.proposedJson,
      userCorrectedJson: record.userCorrectedJson,
      appliedToReceipt: record.appliedToReceipt,
      authorizationGranted: record.authorizationGranted,
      createdAt: record.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    final db = await _db.database;
    await db.update(
      DbSchema.aiExtractions,
      AiExtractionMapper.toMap(saved),
      where: 'id = ?',
      whereArgs: [saved.id],
    );
    return saved;
  }

  Future<AiExtractionRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.aiExtractions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return AiExtractionMapper.fromMap(rows.first);
  }

  Future<List<AiExtractionRecord>> listForReceipt(String receiptId) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.aiExtractions,
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AiExtractionMapper.fromMap).toList();
  }

  Future<List<AiExtractionRecord>> listPendingOrFailed({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      DbSchema.aiExtractions,
      where: "processing_status IN ('pending', 'failed')",
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(AiExtractionMapper.fromMap).toList();
  }
}
