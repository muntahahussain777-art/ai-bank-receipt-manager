enum OfficeAccountStatus {
  active('active'),
  inactive('inactive'),
  archived('archived');

  const OfficeAccountStatus(this.storageValue);
  final String storageValue;

  static OfficeAccountStatus parse(String? value) {
    return switch (value) {
      'inactive' => OfficeAccountStatus.inactive,
      'archived' => OfficeAccountStatus.archived,
      _ => OfficeAccountStatus.active,
    };
  }
}

enum AliasApprovalStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const AliasApprovalStatus(this.storageValue);
  final String storageValue;

  static AliasApprovalStatus parse(String? value) {
    return switch (value) {
      'approved' => AliasApprovalStatus.approved,
      'rejected' => AliasApprovalStatus.rejected,
      _ => AliasApprovalStatus.pending,
    };
  }
}

enum PartyAliasOwnerKind { customer, dealer }
