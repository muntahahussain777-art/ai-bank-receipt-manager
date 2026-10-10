import 'package:ai_bank_receipt_manager/domain/enums/bank_direction.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_flow.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';

class Receipt {
  const Receipt({
    required this.id,
    required this.bankName,
    required this.amount,
    required this.partyName,
    required this.partyKind,
    required this.officeAccount,
    required this.accountingDate,
    required this.transactionDate,
    required this.reference,
    required this.status,
    required this.bankDirection,
    required this.officeFlow,
    required this.adminNote,
    this.officeAccountLabel,
    this.bankSenderName,
    this.bankReceiverName,
    this.winformsReference,
    this.originalImagePath,
    this.mappedAccountId,
    this.customerId,
    this.dealerId,
    this.enteredAt,
    this.entryStatusEntered = false,
    this.priorAmount,
    this.priorPartyName,
    this.priorOfficeAccount,
  });

  final String id;
  final String bankName;
  final double amount;
  final String partyName;
  final PartyKind partyKind;
  final OfficeAccount officeAccount;
  final DateTime accountingDate;
  final DateTime transactionDate;
  final String reference;
  final EntryStatus status;
  final BankDirection bankDirection;
  final OfficeFlow officeFlow;
  final String adminNote;

  /// Dynamic office label from SQLite (preferred over [officeAccount]).
  final String? officeAccountLabel;
  final String? bankSenderName;
  final String? bankReceiverName;
  final String? winformsReference;
  final String? originalImagePath;
  final String? mappedAccountId;
  final String? customerId;
  final String? dealerId;
  final DateTime? enteredAt;

  /// True when SQLite entry_status is entered (tick), even during reconciliation.
  final bool entryStatusEntered;

  /// Financial values previously prepared for manual WinForms entry.
  final double? priorAmount;
  final String? priorPartyName;
  final OfficeAccount? priorOfficeAccount;

  String get officeDisplayLabel =>
      officeAccountLabel ?? officeAccount.displayLabel;

  double get baselineAmount => priorAmount ?? amount;

  String get baselinePartyName => priorPartyName ?? partyName;

  OfficeAccount get baselineOfficeAccount =>
      priorOfficeAccount ?? officeAccount;
}
