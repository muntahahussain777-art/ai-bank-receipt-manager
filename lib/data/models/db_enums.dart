/// Local persistence enums. UI enums stay unchanged.
library;

enum DbReceiptType { received, sent, unknown }

enum DbEntryStatus { pending, entered }

enum DbReviewStatus { pendingReview, approved, needsReconciliation, rejected }

extension DbReceiptTypeCodec on DbReceiptType {
  String get storageValue => switch (this) {
    DbReceiptType.received => 'received',
    DbReceiptType.sent => 'sent',
    DbReceiptType.unknown => 'unknown',
  };

  static DbReceiptType parse(String? value) {
    return switch (value) {
      'received' => DbReceiptType.received,
      'sent' => DbReceiptType.sent,
      _ => DbReceiptType.unknown,
    };
  }
}

extension DbEntryStatusCodec on DbEntryStatus {
  String get storageValue => switch (this) {
    DbEntryStatus.pending => 'pending',
    DbEntryStatus.entered => 'entered',
  };

  static DbEntryStatus parse(String? value) {
    return switch (value) {
      'entered' => DbEntryStatus.entered,
      _ => DbEntryStatus.pending,
    };
  }
}

extension DbReviewStatusCodec on DbReviewStatus {
  String get storageValue => switch (this) {
    DbReviewStatus.pendingReview => 'pending_review',
    DbReviewStatus.approved => 'approved',
    DbReviewStatus.needsReconciliation => 'needs_reconciliation',
    DbReviewStatus.rejected => 'rejected',
  };

  static DbReviewStatus parse(String? value) {
    return switch (value) {
      'approved' => DbReviewStatus.approved,
      'needs_reconciliation' => DbReviewStatus.needsReconciliation,
      'rejected' => DbReviewStatus.rejected,
      _ => DbReviewStatus.pendingReview,
    };
  }
}
