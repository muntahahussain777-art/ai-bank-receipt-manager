/// What the bank receipt says about the bank account itself.
enum BankDirection { credit, debit }

extension BankDirectionDetails on BankDirection {
  String get label => switch (this) {
    BankDirection.credit => 'Bank credit',
    BankDirection.debit => 'Bank debit',
  };
}
