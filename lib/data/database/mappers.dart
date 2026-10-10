import 'dart:convert';

import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';

DateTime dateOnlyUtc(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  return DateTime.utc(local.year, local.month, local.day);
}

String encodeDateOnly(DateTime value) {
  final d = dateOnlyUtc(value);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

DateTime decodeDateOnly(String value) {
  final parts = value.split('-');
  return DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String encodeDateTime(DateTime value) => value.toUtc().toIso8601String();

DateTime decodeDateTime(String value) => DateTime.parse(value).toUtc();

DateTime? decodeDateTimeOrNull(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return decodeDateTime(value);
}

abstract final class ReceiptMapper {
  static Map<String, Object?> toMap(ReceiptRecord record) {
    return {
      'id': record.id,
      'transaction_id': record.transactionId,
      'bank_name': record.bankName,
      'bank_sender_name': record.bankSenderName,
      'bank_receiver_name': record.bankReceiverName,
      'amount': record.amount,
      'currency': record.currency,
      'transaction_date_time': record.transactionDateTime == null
          ? null
          : encodeDateTime(record.transactionDateTime!),
      'accounting_date': encodeDateOnly(record.accountingDate),
      'imported_at': encodeDateTime(record.importedAt),
      'whatsapp_message_date_time': record.whatsappMessageDateTime == null
          ? null
          : encodeDateTime(record.whatsappMessageDateTime!),
      'whatsapp_sender': record.whatsappSender,
      'admin_message': record.adminMessage,
      'original_image_path': record.originalImagePath,
      'image_hash': record.imageHash,
      'receipt_type': record.receiptType.storageValue,
      'mapped_party_id': record.mappedPartyId,
      'mapped_account_id': record.mappedAccountId,
      'dealer_id': record.dealerId,
      'customer_id': record.customerId,
      'confidence_score': record.confidenceScore,
      'review_status': record.reviewStatus.storageValue,
      'entry_status': record.entryStatus.storageValue,
      'entered_at': record.enteredAt == null
          ? null
          : encodeDateTime(record.enteredAt!),
      'entered_by': record.enteredBy,
      'winforms_reference': record.winformsReference,
      'prior_amount': record.priorAmount,
      'prior_party_name': record.priorPartyName,
      'prior_account_id': record.priorAccountId,
      'reconciliation_completed_at': record.reconciliationCompletedAt == null
          ? null
          : encodeDateTime(record.reconciliationCompletedAt!),
      'notes': record.notes,
      'created_at': encodeDateTime(record.createdAt),
      'updated_at': encodeDateTime(record.updatedAt),
      'deleted_at': record.deletedAt == null
          ? null
          : encodeDateTime(record.deletedAt!),
      'import_batch_id': record.importBatchId,
    };
  }

  static ReceiptRecord fromMap(Map<String, Object?> map) {
    return ReceiptRecord(
      id: map['id']! as String,
      transactionId: map['transaction_id'] as String?,
      bankName: map['bank_name']! as String,
      bankSenderName: map['bank_sender_name'] as String?,
      bankReceiverName: map['bank_receiver_name'] as String?,
      amount: (map['amount']! as num).toDouble(),
      currency: map['currency']! as String,
      transactionDateTime: decodeDateTimeOrNull(
        map['transaction_date_time'] as String?,
      ),
      accountingDate: decodeDateOnly(map['accounting_date']! as String),
      importedAt: decodeDateTime(map['imported_at']! as String),
      whatsappMessageDateTime: decodeDateTimeOrNull(
        map['whatsapp_message_date_time'] as String?,
      ),
      whatsappSender: map['whatsapp_sender'] as String?,
      adminMessage: map['admin_message'] as String?,
      originalImagePath: map['original_image_path'] as String?,
      imageHash: map['image_hash'] as String?,
      receiptType: DbReceiptTypeCodec.parse(map['receipt_type'] as String?),
      mappedPartyId: map['mapped_party_id'] as String?,
      mappedAccountId: map['mapped_account_id'] as String?,
      dealerId: map['dealer_id'] as String?,
      customerId: map['customer_id'] as String?,
      confidenceScore: (map['confidence_score'] as num?)?.toDouble(),
      reviewStatus: DbReviewStatusCodec.parse(map['review_status'] as String?),
      entryStatus: DbEntryStatusCodec.parse(map['entry_status'] as String?),
      enteredAt: decodeDateTimeOrNull(map['entered_at'] as String?),
      enteredBy: map['entered_by'] as String?,
      winformsReference: map['winforms_reference'] as String?,
      priorAmount: (map['prior_amount'] as num?)?.toDouble(),
      priorPartyName: map['prior_party_name'] as String?,
      priorAccountId: map['prior_account_id'] as String?,
      reconciliationCompletedAt: decodeDateTimeOrNull(
        map['reconciliation_completed_at'] as String?,
      ),
      notes: map['notes'] as String?,
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
      deletedAt: decodeDateTimeOrNull(map['deleted_at'] as String?),
      importBatchId: map['import_batch_id'] as String?,
    );
  }
}

abstract final class ReconciliationCaseMapper {
  static Map<String, Object?> toMap(ReconciliationCaseRecord record) => {
    'id': record.id,
    'receipt_id': record.receiptId,
    'status': record.status.storageValue,
    'kind': record.kind.storageValue,
    'reason': record.reason,
    'correction_notes': record.correctionNotes,
    'diffs_json': jsonEncode([
      for (final diff in record.diffs) diff.toJson(),
    ]),
    'previous_amount': record.previousAmount,
    'corrected_amount': record.correctedAmount,
    'opened_at': encodeDateTime(record.openedAt),
    'opened_by': record.openedBy,
    'completed_at': record.completedAt == null
        ? null
        : encodeDateTime(record.completedAt!),
    'completed_by': record.completedBy,
    'created_at': encodeDateTime(record.createdAt),
  };

  static ReconciliationCaseRecord fromMap(Map<String, Object?> map) {
    final raw = jsonDecode(map['diffs_json']! as String) as List<dynamic>;
    return ReconciliationCaseRecord(
      id: map['id']! as String,
      receiptId: map['receipt_id']! as String,
      status: ReconciliationCaseStatusCodec.parse(map['status'] as String?),
      kind: ReconciliationCaseKindCodec.parse(map['kind'] as String?),
      reason: map['reason']! as String,
      correctionNotes: map['correction_notes'] as String?,
      diffs: [
        for (final item in raw)
          FinancialFieldDiff.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
      ],
      previousAmount: (map['previous_amount'] as num?)?.toDouble(),
      correctedAmount: (map['corrected_amount'] as num?)?.toDouble(),
      openedAt: decodeDateTime(map['opened_at']! as String),
      openedBy: map['opened_by'] as String?,
      completedAt: decodeDateTimeOrNull(map['completed_at'] as String?),
      completedBy: map['completed_by'] as String?,
      createdAt: decodeDateTime(map['created_at']! as String),
    );
  }
}

abstract final class CustomerMapper {
  static Map<String, Object?> toMap(CustomerRecord record) => {
    'id': record.id,
    'name': record.name,
    'usual_account_id': record.usualAccountId,
    'notes': record.notes,
    'created_at': encodeDateTime(record.createdAt),
    'updated_at': encodeDateTime(record.updatedAt),
    'deleted_at': record.deletedAt == null
        ? null
        : encodeDateTime(record.deletedAt!),
  };

  static CustomerRecord fromMap(Map<String, Object?> map) {
    return CustomerRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      usualAccountId: map['usual_account_id'] as String?,
      notes: map['notes'] as String?,
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
      deletedAt: decodeDateTimeOrNull(map['deleted_at'] as String?),
    );
  }
}

abstract final class DealerMapper {
  static Map<String, Object?> toMap(DealerRecord record) => {
    'id': record.id,
    'name': record.name,
    'usual_account_id': record.usualAccountId,
    'notes': record.notes,
    'created_at': encodeDateTime(record.createdAt),
    'updated_at': encodeDateTime(record.updatedAt),
    'deleted_at': record.deletedAt == null
        ? null
        : encodeDateTime(record.deletedAt!),
  };

  static DealerRecord fromMap(Map<String, Object?> map) {
    return DealerRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      usualAccountId: map['usual_account_id'] as String?,
      notes: map['notes'] as String?,
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
      deletedAt: decodeDateTimeOrNull(map['deleted_at'] as String?),
    );
  }
}

abstract final class AppSettingMapper {
  static Map<String, Object?> toMap(AppSettingRecord record) => {
    'key': record.key,
    'value': record.value,
    'updated_at': encodeDateTime(record.updatedAt),
  };

  static AppSettingRecord fromMap(Map<String, Object?> map) {
    return AppSettingRecord(
      key: map['key']! as String,
      value: map['value']! as String,
      updatedAt: decodeDateTime(map['updated_at']! as String),
    );
  }
}

abstract final class GroqConfigMapper {
  static Map<String, Object?> toMap(GroqApiConfigurationRecord record) => {
    'id': record.id,
    'label': record.label,
    'endpoint': record.endpoint,
    'model_hint': record.modelHint,
    'secure_key_slot': record.secureKeySlot,
    'is_active': record.isActive ? 1 : 0,
    'is_enabled': record.isEnabled ? 1 : 0,
    'masked_key_hint': record.maskedKeyHint,
    'last_error_status': record.lastErrorStatus,
    'last_error_at': record.lastErrorAt == null
        ? null
        : encodeDateTime(record.lastErrorAt!),
    'last_tested_at': record.lastTestedAt == null
        ? null
        : encodeDateTime(record.lastTestedAt!),
    'created_at': encodeDateTime(record.createdAt),
    'updated_at': encodeDateTime(record.updatedAt),
    'deleted_at': record.deletedAt == null
        ? null
        : encodeDateTime(record.deletedAt!),
  };

  static GroqApiConfigurationRecord fromMap(Map<String, Object?> map) {
    return GroqApiConfigurationRecord(
      id: map['id']! as String,
      label: map['label']! as String,
      endpoint: map['endpoint']! as String,
      modelHint: map['model_hint'] as String?,
      secureKeySlot: map['secure_key_slot'] as String?,
      isActive: (map['is_active'] as num?)?.toInt() == 1,
      isEnabled: (map['is_enabled'] as num?)?.toInt() != 0,
      maskedKeyHint: map['masked_key_hint'] as String?,
      lastErrorStatus: map['last_error_status'] as String?,
      lastErrorAt: decodeDateTimeOrNull(map['last_error_at'] as String?),
      lastTestedAt: decodeDateTimeOrNull(map['last_tested_at'] as String?),
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
      deletedAt: decodeDateTimeOrNull(map['deleted_at'] as String?),
    );
  }
}

abstract final class AiExtractionMapper {
  static Map<String, Object?> toMap(AiExtractionRecord record) => {
    'id': record.id,
    'receipt_id': record.receiptId,
    'image_path': record.imagePath,
    'image_hash': record.imageHash,
    'raw_ai_json': record.rawAiJson,
    'raw_parse_status': record.rawParseStatus,
    'processing_status': record.processingStatus.storageValue,
    'error_code': record.errorCode,
    'error_message': record.errorMessage,
    'model_used': record.modelUsed,
    'key_config_id': record.keyConfigId,
    'proposed_json': record.proposedJson,
    'user_corrected_json': record.userCorrectedJson,
    'applied_to_receipt': record.appliedToReceipt ? 1 : 0,
    'authorization_granted': record.authorizationGranted ? 1 : 0,
    'created_at': encodeDateTime(record.createdAt),
    'updated_at': encodeDateTime(record.updatedAt),
  };

  static AiExtractionRecord fromMap(Map<String, Object?> map) {
    return AiExtractionRecord(
      id: map['id']! as String,
      receiptId: map['receipt_id'] as String?,
      imagePath: map['image_path']! as String,
      imageHash: map['image_hash'] as String?,
      rawAiJson: map['raw_ai_json'] as String?,
      rawParseStatus: map['raw_parse_status'] as String?,
      processingStatus: AiProcessingStatusCodec.parse(
        map['processing_status'] as String?,
      ),
      errorCode: map['error_code'] as String?,
      errorMessage: map['error_message'] as String?,
      modelUsed: map['model_used'] as String?,
      keyConfigId: map['key_config_id'] as String?,
      proposedJson: map['proposed_json'] as String?,
      userCorrectedJson: map['user_corrected_json'] as String?,
      appliedToReceipt: (map['applied_to_receipt'] as num?)?.toInt() == 1,
      authorizationGranted:
          (map['authorization_granted'] as num?)?.toInt() == 1,
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
    );
  }
}

abstract final class AuditMapper {
  static Map<String, Object?> toMap(ReceiptAuditHistoryRecord record) => {
    'id': record.id,
    'receipt_id': record.receiptId,
    'field_name': record.fieldName,
    'old_value': record.oldValue,
    'new_value': record.newValue,
    'changed_at': encodeDateTime(record.changedAt),
    'changed_by': record.changedBy,
    'reason': record.reason,
  };

  static ReceiptAuditHistoryRecord fromMap(Map<String, Object?> map) {
    return ReceiptAuditHistoryRecord(
      id: map['id']! as String,
      receiptId: map['receipt_id']! as String,
      fieldName: map['field_name']! as String,
      oldValue: map['old_value'] as String?,
      newValue: map['new_value'] as String?,
      changedAt: decodeDateTime(map['changed_at']! as String),
      changedBy: map['changed_by'] as String?,
      reason: map['reason'] as String?,
    );
  }
}

abstract final class ImportBatchMapper {
  static Map<String, Object?> toMap(ImportBatchRecord record) => {
    'id': record.id,
    'accounting_date': encodeDateOnly(record.accountingDate),
    'imported_at': encodeDateTime(record.importedAt),
    'source': record.source,
    'receipt_count': record.receiptCount,
    'file_count': record.fileCount,
    'success_count': record.successCount,
    'failed_count': record.failedCount,
    'duplicate_count': record.duplicateCount,
    'pending_review_count': record.pendingReviewCount,
    'batch_status': record.batchStatus.storageValue,
    'notes': record.notes,
    'created_at': encodeDateTime(record.createdAt),
  };

  static ImportBatchRecord fromMap(Map<String, Object?> map) {
    return ImportBatchRecord(
      id: map['id']! as String,
      accountingDate: decodeDateOnly(map['accounting_date']! as String),
      importedAt: decodeDateTime(map['imported_at']! as String),
      source: map['source']! as String,
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      fileCount: (map['file_count'] as num?)?.toInt() ?? 0,
      successCount: (map['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (map['failed_count'] as num?)?.toInt() ?? 0,
      duplicateCount: (map['duplicate_count'] as num?)?.toInt() ?? 0,
      pendingReviewCount: (map['pending_review_count'] as num?)?.toInt() ?? 0,
      batchStatus: ImportBatchStatusCodec.parse(map['batch_status'] as String?),
      notes: map['notes'] as String?,
      createdAt: decodeDateTime(map['created_at']! as String),
    );
  }
}

abstract final class ImportQueueItemMapper {
  static Map<String, Object?> toMap(ImportQueueItemRecord record) => {
    'id': record.id,
    'batch_id': record.batchId,
    'group_id': record.groupId,
    'source_kind': record.sourceKind,
    'original_uri': record.originalUri,
    'stored_path': record.storedPath,
    'image_hash': record.imageHash,
    'mime_type': record.mimeType,
    'display_name': record.displayName,
    'queue_status': record.queueStatus.storageValue,
    'error_message': record.errorMessage,
    'extraction_id': record.extractionId,
    'receipt_id': record.receiptId,
    'duplicate_of_receipt_id': record.duplicateOfReceiptId,
    'admin_note_override': record.adminNoteOverride,
    'retry_count': record.retryCount,
    'created_at': encodeDateTime(record.createdAt),
    'updated_at': encodeDateTime(record.updatedAt),
  };

  static ImportQueueItemRecord fromMap(Map<String, Object?> map) {
    return ImportQueueItemRecord(
      id: map['id']! as String,
      batchId: map['batch_id']! as String,
      groupId: map['group_id'] as String?,
      sourceKind: map['source_kind']! as String,
      originalUri: map['original_uri'] as String?,
      storedPath: map['stored_path']! as String,
      imageHash: map['image_hash'] as String?,
      mimeType: map['mime_type'] as String?,
      displayName: map['display_name'] as String?,
      queueStatus: ImportQueueStatusCodec.parse(map['queue_status'] as String?),
      errorMessage: map['error_message'] as String?,
      extractionId: map['extraction_id'] as String?,
      receiptId: map['receipt_id'] as String?,
      duplicateOfReceiptId: map['duplicate_of_receipt_id'] as String?,
      adminNoteOverride: map['admin_note_override'] as String?,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
    );
  }
}
