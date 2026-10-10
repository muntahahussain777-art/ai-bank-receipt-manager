import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';

class Party {
  const Party({
    required this.id,
    required this.name,
    required this.kind,
    required this.usualAccount,
    required this.note,
  });

  final String id;
  final String name;
  final PartyKind kind;
  final OfficeAccount usualAccount;
  final String note;
}
