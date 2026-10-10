import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/utils/alias_normalize.dart';

abstract final class OfficeAccountMapper {
  static Map<String, Object?> toMap(OfficeAccountRecord record) {
    final display = record.displayName;
    return {
      'id': record.id,
      'office_key': record.officeKey ?? 'acct_${record.id}',
      'short_name': display,
      'legal_name': display,
      'display_name': display,
      'status': record.status.storageValue,
      'notes': record.notes,
      'created_at': encodeDateTime(record.createdAt),
      'updated_at': encodeDateTime(record.updatedAt),
      'archived_at': record.archivedAt == null
          ? null
          : encodeDateTime(record.archivedAt!),
      'deleted_at': record.deletedAt == null
          ? null
          : encodeDateTime(record.deletedAt!),
    };
  }

  static OfficeAccountRecord fromMap(Map<String, Object?> map) {
    final display = (map['display_name'] as String?)?.trim().isNotEmpty == true
        ? map['display_name']! as String
        : map['short_name']! as String;
    return OfficeAccountRecord(
      id: map['id']! as String,
      displayName: display,
      status: OfficeAccountStatus.parse(map['status'] as String?),
      officeKey: map['office_key'] as String?,
      notes: map['notes'] as String?,
      createdAt: decodeDateTime(map['created_at']! as String),
      updatedAt: decodeDateTime(map['updated_at']! as String),
      archivedAt: decodeDateTimeOrNull(map['archived_at'] as String?),
      deletedAt: decodeDateTimeOrNull(map['deleted_at'] as String?),
    );
  }
}

abstract final class OfficeAliasMapper {
  static Map<String, Object?> toMap(OfficeAccountAliasRecord record) => {
    'id': record.id,
    'office_account_id': record.officeAccountId,
    'alias_name': record.aliasName,
    'normalized_alias': record.normalizedAlias,
    'approval_status': record.approvalStatus.storageValue,
    'created_at': encodeDateTime(record.createdAt),
  };

  static OfficeAccountAliasRecord fromMap(Map<String, Object?> map) {
    return OfficeAccountAliasRecord(
      id: map['id']! as String,
      officeAccountId: map['office_account_id']! as String,
      aliasName: map['alias_name']! as String,
      normalizedAlias: map['normalized_alias']! as String,
      approvalStatus: AliasApprovalStatus.parse(
        map['approval_status'] as String?,
      ),
      createdAt: decodeDateTime(map['created_at']! as String),
    );
  }
}

abstract final class PartyAliasMapper {
  static Map<String, Object?> toCustomerMap(PartyAliasRecord record) => {
    'id': record.id,
    'customer_id': record.ownerId,
    'alias_name': record.aliasName,
    'normalized_alias': record.normalizedAlias,
    'approval_status': record.approvalStatus.storageValue,
    'created_at': encodeDateTime(record.createdAt),
  };

  static Map<String, Object?> toDealerMap(PartyAliasRecord record) => {
    'id': record.id,
    'dealer_id': record.ownerId,
    'alias_name': record.aliasName,
    'normalized_alias': record.normalizedAlias,
    'approval_status': record.approvalStatus.storageValue,
    'created_at': encodeDateTime(record.createdAt),
  };

  static PartyAliasRecord fromCustomerMap(Map<String, Object?> map) {
    return PartyAliasRecord(
      id: map['id']! as String,
      ownerKind: PartyAliasOwnerKind.customer,
      ownerId: map['customer_id']! as String,
      aliasName: map['alias_name']! as String,
      normalizedAlias: map['normalized_alias']! as String,
      approvalStatus: AliasApprovalStatus.parse(
        map['approval_status'] as String?,
      ),
      createdAt: decodeDateTime(map['created_at']! as String),
    );
  }

  static PartyAliasRecord fromDealerMap(Map<String, Object?> map) {
    return PartyAliasRecord(
      id: map['id']! as String,
      ownerKind: PartyAliasOwnerKind.dealer,
      ownerId: map['dealer_id']! as String,
      aliasName: map['alias_name']! as String,
      normalizedAlias: map['normalized_alias']! as String,
      approvalStatus: AliasApprovalStatus.parse(
        map['approval_status'] as String?,
      ),
      createdAt: decodeDateTime(map['created_at']! as String),
    );
  }
}

// Re-export normalize for mappers that need it during writes.
String normalizedAliasValue(String alias) => normalizeAlias(alias);
