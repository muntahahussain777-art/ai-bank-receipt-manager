import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';

/// Stable seed ids. Used only for the one-time default insert.
abstract final class DefaultOfficeAccountIds {
  static const mutalib = 'account-mutalib';
  static const ad = 'account-ad';
  static const seedFlagKey = 'office_accounts_defaults_seeded';
}

class OfficeAccountRecord {
  const OfficeAccountRecord({
    required this.id,
    required this.displayName,
    required this.status,
    this.officeKey,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    this.deletedAt,
  });

  final String id;
  final String displayName;
  final OfficeAccountStatus status;

  /// Optional stable key for the default seed rows only.
  final String? officeKey;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;

  bool get isSelectableForNewEntries =>
      status == OfficeAccountStatus.active && deletedAt == null;

  bool get isArchived => status == OfficeAccountStatus.archived;

  OfficeAccountRecord copyWith({
    String? displayName,
    OfficeAccountStatus? status,
    String? officeKey,
    String? notes,
    DateTime? updatedAt,
    DateTime? archivedAt,
    DateTime? deletedAt,
    bool clearArchivedAt = false,
    bool clearDeletedAt = false,
  }) {
    return OfficeAccountRecord(
      id: id,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      officeKey: officeKey ?? this.officeKey,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

class OfficeAccountAliasRecord {
  const OfficeAccountAliasRecord({
    required this.id,
    required this.officeAccountId,
    required this.aliasName,
    required this.normalizedAlias,
    required this.approvalStatus,
    required this.createdAt,
  });

  final String id;
  final String officeAccountId;
  final String aliasName;
  final String normalizedAlias;
  final AliasApprovalStatus approvalStatus;
  final DateTime createdAt;
}

class PartyAliasRecord {
  const PartyAliasRecord({
    required this.id,
    required this.ownerKind,
    required this.ownerId,
    required this.aliasName,
    required this.normalizedAlias,
    required this.approvalStatus,
    required this.createdAt,
  });

  final String id;
  final PartyAliasOwnerKind ownerKind;
  final String ownerId;
  final String aliasName;
  final String normalizedAlias;
  final AliasApprovalStatus approvalStatus;
  final DateTime createdAt;
}

class OfficeAccountActivity {
  const OfficeAccountActivity({
    required this.account,
    required this.received,
    required this.sent,
    required this.count,
    this.primaryAlias,
  });

  final OfficeAccountRecord account;
  final double received;
  final double sent;
  final int count;
  final String? primaryAlias;
}
