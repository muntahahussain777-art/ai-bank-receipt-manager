enum PartyKind { customer, dealer }

extension PartyKindDetails on PartyKind {
  String get label => switch (this) {
    PartyKind.customer => 'Customer',
    PartyKind.dealer => 'Dealer',
  };
}
