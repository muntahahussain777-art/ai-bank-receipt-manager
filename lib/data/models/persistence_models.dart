import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';

class ReceiptRecord {
  const ReceiptRecord({
    required this.id,
    this.transactionId,
    required this.bankName,
    this.bankSenderName,
    this.bankReceiverName,
    required this.amount,
    required this.currency,
    this.transactionDateTime,
    required this.accountingDate,
    required this.importedAt,
    this.whatsappMessageDateTime,
    this.whatsappSender,
    this.adminMessage,
    this.originalImagePath,
    this.imageHash,
    required this.receiptType,
    this.mappedPartyId,
    this.mappedAccountId,
    this.dealerId,
    this.customerId,
    this.confidenceScore,
    required this.reviewStatus,
    required this.entryStatus,
    this.enteredAt,
    this.enteredBy,
    this.winformsReference,
    this.priorAmount,
    this.priorPartyName,
    this.priorAccountId,
    this.reconciliationCompletedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.importBatchId,
  });

  final String id;
  final String? transactionId;
  final String bankName;
  final String? bankSenderName;
  final String? bankReceiverName;
  final double amount;
  final String currency;
  final DateTime? transactionDateTime;
  final DateTime accountingDate;
  final DateTime importedAt;
  final DateTime? whatsappMessageDateTime;
  final String? whatsappSender;
  final String? adminMessage;
  final String? originalImagePath;
  final String? imageHash;
  final DbReceiptType receiptType;
  final String? mappedPartyId;
  final String? mappedAccountId;
  final String? dealerId;
  final String? customerId;
  final double? confidenceScore;
  final DbReviewStatus reviewStatus;
  final DbEntryStatus entryStatus;
  final DateTime? enteredAt;
  final String? enteredBy;
  final String? winformsReference;
  final double? priorAmount;
  final String? priorPartyName;
  final String? priorAccountId;
  final DateTime? reconciliationCompletedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? importBatchId;

  bool get isDeleted => deletedAt != null;

  bool get hasUnresolvedFinancialConflict =>
      reviewStatus == DbReviewStatus.needsReconciliation;

  ReceiptRecord copyWith({
    String? id,
    String? transactionId,
    String? bankName,
    String? bankSenderName,
    String? bankReceiverName,
    double? amount,
    String? currency,
    DateTime? transactionDateTime,
    DateTime? accountingDate,
    DateTime? importedAt,
    DateTime? whatsappMessageDateTime,
    String? whatsappSender,
    String? adminMessage,
    String? originalImagePath,
    String? imageHash,
    DbReceiptType? receiptType,
    String? mappedPartyId,
    String? mappedAccountId,
    String? dealerId,
    String? customerId,
    double? confidenceScore,
    DbReviewStatus? reviewStatus,
    DbEntryStatus? entryStatus,
    DateTime? enteredAt,
    String? enteredBy,
    String? winformsReference,
    double? priorAmount,
    String? priorPartyName,
    String? priorAccountId,
    DateTime? reconciliationCompletedAt,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? importBatchId,
    bool clearDeletedAt = false,
    bool clearEnteredAt = false,
    bool clearEnteredBy = false,
    bool clearWinformsReference = false,
    bool clearReconciliationCompletedAt = false,
    bool clearMappedAccountId = false,
    bool clearCustomerId = false,
    bool clearDealerId = false,
    bool clearTransactionId = false,
  }) {
    return ReceiptRecord(
      id: id ?? this.id,
      transactionId: clearTransactionId
          ? null
          : (transactionId ?? this.transactionId),
      bankName: bankName ?? this.bankName,
      bankSenderName: bankSenderName ?? this.bankSenderName,
      bankReceiverName: bankReceiverName ?? this.bankReceiverName,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      transactionDateTime: transactionDateTime ?? this.transactionDateTime,
      accountingDate: accountingDate ?? this.accountingDate,
      importedAt: importedAt ?? this.importedAt,
      whatsappMessageDateTime:
          whatsappMessageDateTime ?? this.whatsappMessageDateTime,
      whatsappSender: whatsappSender ?? this.whatsappSender,
      adminMessage: adminMessage ?? this.adminMessage,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      imageHash: imageHash ?? this.imageHash,
      receiptType: receiptType ?? this.receiptType,
      mappedPartyId: mappedPartyId ?? this.mappedPartyId,
      mappedAccountId: clearMappedAccountId
          ? null
          : (mappedAccountId ?? this.mappedAccountId),
      dealerId: clearDealerId ? null : (dealerId ?? this.dealerId),
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      confidenceScore: confidenceScore ?? this.confidenceScore,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      entryStatus: entryStatus ?? this.entryStatus,
      enteredAt: clearEnteredAt ? null : (enteredAt ?? this.enteredAt),
      enteredBy: clearEnteredBy ? null : (enteredBy ?? this.enteredBy),
      winformsReference: clearWinformsReference
          ? null
          : (winformsReference ?? this.winformsReference),
      priorAmount: priorAmount ?? this.priorAmount,
      priorPartyName: priorPartyName ?? this.priorPartyName,
      priorAccountId: priorAccountId ?? this.priorAccountId,
      reconciliationCompletedAt: clearReconciliationCompletedAt
          ? null
          : (reconciliationCompletedAt ?? this.reconciliationCompletedAt),
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      importBatchId: importBatchId ?? this.importBatchId,
    );
  }
}

enum ReconciliationCaseStatus { open, completed }

enum ReconciliationCaseKind { financialEdit, deletion, reopen }

extension ReconciliationCaseStatusCodec on ReconciliationCaseStatus {
  String get storageValue => switch (this) {
    ReconciliationCaseStatus.open => 'open',
    ReconciliationCaseStatus.completed => 'completed',
  };

  static ReconciliationCaseStatus parse(String? value) {
    return switch (value) {
      'completed' => ReconciliationCaseStatus.completed,
      _ => ReconciliationCaseStatus.open,
    };
  }
}

extension ReconciliationCaseKindCodec on ReconciliationCaseKind {
  String get storageValue => switch (this) {
    ReconciliationCaseKind.financialEdit => 'financial_edit',
    ReconciliationCaseKind.deletion => 'deletion',
    ReconciliationCaseKind.reopen => 'reopen',
  };

  static ReconciliationCaseKind parse(String? value) {
    return switch (value) {
      'deletion' => ReconciliationCaseKind.deletion,
      'reopen' => ReconciliationCaseKind.reopen,
      _ => ReconciliationCaseKind.financialEdit,
    };
  }
}

/// Immutable snapshot of one financial field change inside a reconciliation case.
class FinancialFieldDiff {
  const FinancialFieldDiff({
    required this.field,
    required this.label,
    this.oldValue,
    this.newValue,
  });

  final String field;
  final String label;
  final String? oldValue;
  final String? newValue;

  Map<String, Object?> toJson() => {
    'field': field,
    'label': label,
    'oldValue': oldValue,
    'newValue': newValue,
  };

  static FinancialFieldDiff fromJson(Map<String, Object?> json) {
    return FinancialFieldDiff(
      field: json['field']! as String,
      label: json['label']! as String,
      oldValue: json['oldValue'] as String?,
      newValue: json['newValue'] as String?,
    );
  }
}

class ReconciliationCaseRecord {
  const ReconciliationCaseRecord({
    required this.id,
    required this.receiptId,
    required this.status,
    required this.kind,
    required this.reason,
    this.correctionNotes,
    required this.diffs,
    this.previousAmount,
    this.correctedAmount,
    required this.openedAt,
    this.openedBy,
    this.completedAt,
    this.completedBy,
    required this.createdAt,
  });

  final String id;
  final String receiptId;
  final ReconciliationCaseStatus status;
  final ReconciliationCaseKind kind;
  final String reason;
  final String? correctionNotes;
  final List<FinancialFieldDiff> diffs;
  final double? previousAmount;
  final double? correctedAmount;
  final DateTime openedAt;
  final String? openedBy;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime createdAt;

  bool get isOpen => status == ReconciliationCaseStatus.open;

  ReconciliationCaseRecord copyWith({
    ReconciliationCaseStatus? status,
    String? correctionNotes,
    DateTime? completedAt,
    String? completedBy,
  }) {
    return ReconciliationCaseRecord(
      id: id,
      receiptId: receiptId,
      status: status ?? this.status,
      kind: kind,
      reason: reason,
      correctionNotes: correctionNotes ?? this.correctionNotes,
      diffs: diffs,
      previousAmount: previousAmount,
      correctedAmount: correctedAmount,
      openedAt: openedAt,
      openedBy: openedBy,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      createdAt: createdAt,
    );
  }
}

/// Lightweight filter for efficient SQLite desk queries (no image blobs).
class ReceiptListFilter {
  const ReceiptListFilter({
    this.accountingDate,
    this.accountingDateFrom,
    this.accountingDateTo,
    this.bankName,
    this.mappedAccountId,
    this.customerId,
    this.dealerId,
    this.entryStatus,
    this.reviewStatus,
    this.searchText,
    this.includeDeleted = false,
    this.limit,
    this.offset,
  });

  final DateTime? accountingDate;
  final DateTime? accountingDateFrom;
  final DateTime? accountingDateTo;
  final String? bankName;
  final String? mappedAccountId;
  final String? customerId;
  final String? dealerId;
  final DbEntryStatus? entryStatus;
  final DbReviewStatus? reviewStatus;
  final String? searchText;
  final bool includeDeleted;
  final int? limit;
  final int? offset;
}

class DailyDeskSummary {
  const DailyDeskSummary({
    required this.accountingDate,
    required this.totalCount,
    required this.totalReceived,
    required this.totalSent,
    required this.pendingCount,
    required this.enteredCount,
    required this.reconciliationCount,
    required this.countByAccountId,
    required this.receivedByAccountId,
    required this.sentByAccountId,
  });

  final DateTime accountingDate;
  final int totalCount;
  final double totalReceived;
  final double totalSent;
  final int pendingCount;
  final int enteredCount;
  final int reconciliationCount;
  final Map<String, int> countByAccountId;
  final Map<String, double> receivedByAccountId;
  final Map<String, double> sentByAccountId;
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    this.usualAccountId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? usualAccountId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class DealerRecord {
  const DealerRecord({
    required this.id,
    required this.name,
    this.usualAccountId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? usualAccountId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class AppSettingRecord {
  const AppSettingRecord({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;
}

class GroqApiConfigurationRecord {
  const GroqApiConfigurationRecord({
    required this.id,
    required this.label,
    required this.endpoint,
    this.modelHint,
    this.secureKeySlot,
    required this.isActive,
    this.isEnabled = true,
    this.maskedKeyHint,
    this.lastErrorStatus,
    this.lastErrorAt,
    this.lastTestedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String label;
  final String endpoint;
  final String? modelHint;

  /// Reference to platform secure storage. Never a plain API key.
  final String? secureKeySlot;

  /// Preferred key when true (at most one preferred among non-deleted rows).
  final bool isActive;

  /// Disabled keys are skipped by fallback.
  final bool isEnabled;

  /// Masked display only (e.g. gsk_…abcd). Never the full secret.
  final String? maskedKeyHint;
  final String? lastErrorStatus;
  final DateTime? lastErrorAt;
  final DateTime? lastTestedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  GroqApiConfigurationRecord copyWith({
    String? id,
    String? label,
    String? endpoint,
    String? modelHint,
    String? secureKeySlot,
    bool? isActive,
    bool? isEnabled,
    String? maskedKeyHint,
    String? lastErrorStatus,
    DateTime? lastErrorAt,
    DateTime? lastTestedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearLastError = false,
  }) {
    return GroqApiConfigurationRecord(
      id: id ?? this.id,
      label: label ?? this.label,
      endpoint: endpoint ?? this.endpoint,
      modelHint: modelHint ?? this.modelHint,
      secureKeySlot: secureKeySlot ?? this.secureKeySlot,
      isActive: isActive ?? this.isActive,
      isEnabled: isEnabled ?? this.isEnabled,
      maskedKeyHint: maskedKeyHint ?? this.maskedKeyHint,
      lastErrorStatus: clearLastError
          ? null
          : (lastErrorStatus ?? this.lastErrorStatus),
      lastErrorAt: clearLastError ? null : (lastErrorAt ?? this.lastErrorAt),
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

enum AiProcessingStatus {
  pending,
  succeeded,
  failed,
  needsReview,
  proposed,
}

extension AiProcessingStatusCodec on AiProcessingStatus {
  String get storageValue => switch (this) {
    AiProcessingStatus.pending => 'pending',
    AiProcessingStatus.succeeded => 'succeeded',
    AiProcessingStatus.failed => 'failed',
    AiProcessingStatus.needsReview => 'needs_review',
    AiProcessingStatus.proposed => 'proposed',
  };

  static AiProcessingStatus parse(String? value) {
    return switch (value) {
      'succeeded' => AiProcessingStatus.succeeded,
      'failed' => AiProcessingStatus.failed,
      'needs_review' => AiProcessingStatus.needsReview,
      'proposed' => AiProcessingStatus.proposed,
      _ => AiProcessingStatus.pending,
    };
  }
}

/// Raw AI extraction kept separate from user-corrected receipt fields.
class AiExtractionRecord {
  const AiExtractionRecord({
    required this.id,
    this.receiptId,
    required this.imagePath,
    this.imageHash,
    this.rawAiJson,
    this.rawParseStatus,
    required this.processingStatus,
    this.errorCode,
    this.errorMessage,
    this.modelUsed,
    this.keyConfigId,
    this.proposedJson,
    this.userCorrectedJson,
    this.appliedToReceipt = false,
    required this.authorizationGranted,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? receiptId;
  final String imagePath;
  final String? imageHash;
  final String? rawAiJson;
  final String? rawParseStatus;
  final AiProcessingStatus processingStatus;
  final String? errorCode;
  final String? errorMessage;
  final String? modelUsed;
  final String? keyConfigId;
  final String? proposedJson;
  final String? userCorrectedJson;
  final bool appliedToReceipt;
  final bool authorizationGranted;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ReceiptAuditHistoryRecord {
  const ReceiptAuditHistoryRecord({
    required this.id,
    required this.receiptId,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    required this.changedAt,
    this.changedBy,
    this.reason,
  });

  final String id;
  final String receiptId;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final DateTime changedAt;
  final String? changedBy;
  final String? reason;
}

enum ImportBatchStatus { open, processing, completed, cancelled }

extension ImportBatchStatusCodec on ImportBatchStatus {
  String get storageValue => switch (this) {
    ImportBatchStatus.open => 'open',
    ImportBatchStatus.processing => 'processing',
    ImportBatchStatus.completed => 'completed',
    ImportBatchStatus.cancelled => 'cancelled',
  };

  static ImportBatchStatus parse(String? value) {
    return switch (value) {
      'processing' => ImportBatchStatus.processing,
      'completed' => ImportBatchStatus.completed,
      'cancelled' => ImportBatchStatus.cancelled,
      _ => ImportBatchStatus.open,
    };
  }
}

enum ImportQueueStatus {
  queued,
  processing,
  awaitingReview,
  succeeded,
  failed,
  skippedDuplicate,
  cancelled,
}

extension ImportQueueStatusCodec on ImportQueueStatus {
  String get storageValue => switch (this) {
    ImportQueueStatus.queued => 'queued',
    ImportQueueStatus.processing => 'processing',
    ImportQueueStatus.awaitingReview => 'awaiting_review',
    ImportQueueStatus.succeeded => 'succeeded',
    ImportQueueStatus.failed => 'failed',
    ImportQueueStatus.skippedDuplicate => 'skipped_duplicate',
    ImportQueueStatus.cancelled => 'cancelled',
  };

  static ImportQueueStatus parse(String? value) {
    return switch (value) {
      'processing' => ImportQueueStatus.processing,
      'awaiting_review' => ImportQueueStatus.awaitingReview,
      'succeeded' => ImportQueueStatus.succeeded,
      'failed' => ImportQueueStatus.failed,
      'skipped_duplicate' => ImportQueueStatus.skippedDuplicate,
      'cancelled' => ImportQueueStatus.cancelled,
      _ => ImportQueueStatus.queued,
    };
  }
}

class ImportBatchRecord {
  const ImportBatchRecord({
    required this.id,
    required this.accountingDate,
    required this.importedAt,
    required this.source,
    required this.receiptCount,
    this.fileCount = 0,
    this.successCount = 0,
    this.failedCount = 0,
    this.duplicateCount = 0,
    this.pendingReviewCount = 0,
    this.batchStatus = ImportBatchStatus.open,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final DateTime accountingDate;
  final DateTime importedAt;
  final String source;
  final int receiptCount;
  final int fileCount;
  final int successCount;
  final int failedCount;
  final int duplicateCount;
  final int pendingReviewCount;
  final ImportBatchStatus batchStatus;
  final String? notes;
  final DateTime createdAt;

  ImportBatchRecord copyWith({
    int? receiptCount,
    int? fileCount,
    int? successCount,
    int? failedCount,
    int? duplicateCount,
    int? pendingReviewCount,
    ImportBatchStatus? batchStatus,
    String? notes,
  }) {
    return ImportBatchRecord(
      id: id,
      accountingDate: accountingDate,
      importedAt: importedAt,
      source: source,
      receiptCount: receiptCount ?? this.receiptCount,
      fileCount: fileCount ?? this.fileCount,
      successCount: successCount ?? this.successCount,
      failedCount: failedCount ?? this.failedCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      pendingReviewCount: pendingReviewCount ?? this.pendingReviewCount,
      batchStatus: batchStatus ?? this.batchStatus,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }
}

class ImportQueueItemRecord {
  const ImportQueueItemRecord({
    required this.id,
    required this.batchId,
    this.groupId,
    required this.sourceKind,
    this.originalUri,
    required this.storedPath,
    this.imageHash,
    this.mimeType,
    this.displayName,
    required this.queueStatus,
    this.errorMessage,
    this.extractionId,
    this.receiptId,
    this.duplicateOfReceiptId,
    this.adminNoteOverride,
    this.retryCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String batchId;
  final String? groupId;
  final String sourceKind;
  final String? originalUri;
  final String storedPath;
  final String? imageHash;
  final String? mimeType;
  final String? displayName;
  final ImportQueueStatus queueStatus;
  final String? errorMessage;
  final String? extractionId;
  final String? receiptId;
  final String? duplicateOfReceiptId;
  final String? adminNoteOverride;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class DuplicateMatch {
  const DuplicateMatch({required this.existing, required this.reasons});

  final ReceiptRecord existing;
  final List<String> reasons;
}

class ReceiptImportDraft {
  const ReceiptImportDraft({
    this.id,
    this.transactionId,
    required this.bankName,
    this.bankSenderName,
    this.bankReceiverName,
    required this.amount,
    this.currency = 'PKR',
    this.transactionDateTime,
    this.whatsappMessageDateTime,
    this.whatsappSender,
    this.adminMessage,
    this.originalImagePath,
    this.imageHash,
    this.receiptType = DbReceiptType.unknown,
    this.mappedPartyId,
    this.mappedAccountId,
    this.dealerId,
    this.customerId,
    this.confidenceScore,
    this.reviewStatus = DbReviewStatus.pendingReview,
    this.notes,
  });

  final String? id;
  final String? transactionId;
  final String bankName;
  final String? bankSenderName;
  final String? bankReceiverName;
  final double amount;
  final String currency;
  final DateTime? transactionDateTime;
  final DateTime? whatsappMessageDateTime;
  final String? whatsappSender;
  final String? adminMessage;
  final String? originalImagePath;
  final String? imageHash;
  final DbReceiptType receiptType;
  final String? mappedPartyId;
  final String? mappedAccountId;
  final String? dealerId;
  final String? customerId;
  final double? confidenceScore;
  final DbReviewStatus reviewStatus;
  final String? notes;
}
