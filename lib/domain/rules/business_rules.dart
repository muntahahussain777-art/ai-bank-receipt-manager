/// Office rules preserved across phases. Accounts are dynamic after Phase 3.
abstract final class BusinessRules {
  /// Default seed display names only — not permanent identities.
  static const defaultMutalibDisplayName = 'Mutalib';
  static const defaultMutalibBankAlias = 'Azlan Traders';
  static const defaultAdDisplayName = 'AD';
  static const defaultAdBankAlias = 'Habib Enterprise';

  @Deprecated('Use defaultMutalibDisplayName — accounts are dynamic.')
  static const mutalibShort = defaultMutalibDisplayName;
  @Deprecated('Use defaultMutalibBankAlias — accounts are dynamic.')
  static const mutalibLegal = defaultMutalibBankAlias;
  @Deprecated('Use defaultAdDisplayName — accounts are dynamic.')
  static const adShort = defaultAdDisplayName;
  @Deprecated('Use defaultAdBankAlias — accounts are dynamic.')
  static const adLegal = defaultAdBankAlias;

  static const officeEntrySafety =
      'This app prepares daily lists for manual office entry. It never '
      'posts or changes entries in the office accounting system.';

  /// @Deprecated Prefer [officeEntrySafety] for user-facing copy.
  static const winFormsSafety = officeEntrySafety;

  static const directionRule =
      'Bank transaction direction and office accounting attribution are '
      'different. A credit or debit describes the bank account. The office '
      'customer or dealer comes from the WhatsApp admin note.';

  static const liveDataBanner =
      'Totals and lists use your saved local records for the selected '
      'accounting date. This app never changes the office accounting system.';

  /// @Deprecated Prefer [liveDataBanner].
  static const previewBanner = liveDataBanner;

  static const rules = <String>[
    'WhatsApp screenshots may contain a bank receipt and an admin message.',
    'Office accounts are dynamic. Mutalib and AD are only the default seeded accounts.',
    'Customer to any active office account is proposed as incoming.',
    'Any active office account to a dealer is proposed as outgoing.',
    'The WhatsApp admin note identifies a possible office customer or dealer, but is not bank-direction proof.',
    'Bank transaction direction and office accounting attribution are different.',
    'The app prepares daily lists for manual entry into the office accounting system.',
    'The app must never directly modify the office accounting system or its database.',
  ];
}
