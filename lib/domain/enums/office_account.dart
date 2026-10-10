import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';

enum OfficeAccount { mutalib, ad }

extension OfficeAccountDetails on OfficeAccount {
  /// Preview-desk labels only. Live office accounts come from SQLite.
  String get shortName => switch (this) {
    OfficeAccount.mutalib => BusinessRules.defaultMutalibDisplayName,
    OfficeAccount.ad => BusinessRules.defaultAdDisplayName,
  };

  String get legalName => switch (this) {
    OfficeAccount.mutalib => BusinessRules.defaultMutalibBankAlias,
    OfficeAccount.ad => BusinessRules.defaultAdBankAlias,
  };

  String get displayLabel => '$shortName ($legalName)';
}
