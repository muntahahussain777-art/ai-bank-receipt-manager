enum EntryStatus { pending, entered, needsReconciliation }

extension EntryStatusDetails on EntryStatus {
  String get label => switch (this) {
    EntryStatus.pending => 'Pending',
    EntryStatus.entered => 'Entered',
    EntryStatus.needsReconciliation => 'Needs reconciliation',
  };

  /// Desk order for a daily WinForms list: still to enter, then corrections.
  int get deskOrder => switch (this) {
    EntryStatus.pending => 0,
    EntryStatus.needsReconciliation => 1,
    EntryStatus.entered => 2,
  };
}
