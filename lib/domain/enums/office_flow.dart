/// Who the office attributes the money to. This is not the bank direction.
enum OfficeFlow { customerToOffice, officeToDealer }

extension OfficeFlowDetails on OfficeFlow {
  String get label => switch (this) {
    OfficeFlow.customerToOffice => 'Customer to office',
    OfficeFlow.officeToDealer => 'Office to dealer',
  };
}
