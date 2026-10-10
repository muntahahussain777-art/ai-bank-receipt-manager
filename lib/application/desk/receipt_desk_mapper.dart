import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/enums/bank_direction.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_flow.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';

abstract final class ReceiptDeskMapper {
  static EntryStatus composeStatus(ReceiptRecord record) {
    if (record.reviewStatus == DbReviewStatus.needsReconciliation) {
      return EntryStatus.needsReconciliation;
    }
    if (record.entryStatus == DbEntryStatus.entered) {
      return EntryStatus.entered;
    }
    return EntryStatus.pending;
  }

  static Receipt toDomain(
    ReceiptRecord record, {
    String? partyName,
    PartyKind? partyKind,
    String? officeAccountLabel,
    OfficeAccountRecord? officeAccount,
  }) {
    final kind = partyKind ??
        (record.dealerId != null
            ? PartyKind.dealer
            : PartyKind.customer);
    final name = partyName ??
        ((record.adminMessage?.trim().isNotEmpty == true)
            ? record.adminMessage!.trim()
            : (record.bankSenderName ??
                  record.bankReceiverName ??
                  'Unassigned'));
    final label = officeAccountLabel ??
        officeAccount?.displayName ??
        'Unassigned office';
    final previewOffice = _previewOffice(officeAccount);

    return Receipt(
      id: record.id,
      bankName: record.bankName,
      amount: record.amount,
      partyName: name,
      partyKind: kind,
      officeAccount: previewOffice,
      officeAccountLabel: label,
      accountingDate: record.accountingDate,
      transactionDate:
          record.transactionDateTime ?? record.accountingDate,
      reference: record.transactionId ?? '(no reference)',
      status: composeStatus(record),
      bankDirection: record.receiptType == DbReceiptType.sent
          ? BankDirection.debit
          : BankDirection.credit,
      officeFlow: kind == PartyKind.dealer
          ? OfficeFlow.officeToDealer
          : OfficeFlow.customerToOffice,
      adminNote: record.adminMessage ?? '',
      bankSenderName: record.bankSenderName,
      bankReceiverName: record.bankReceiverName,
      winformsReference: record.winformsReference,
      originalImagePath: record.originalImagePath,
      mappedAccountId: record.mappedAccountId,
      customerId: record.customerId,
      dealerId: record.dealerId,
      enteredAt: record.enteredAt,
      entryStatusEntered: record.entryStatus == DbEntryStatus.entered,
      priorAmount: record.priorAmount,
      priorPartyName: record.priorPartyName,
    );
  }

  static OfficeAccount _previewOffice(OfficeAccountRecord? account) {
    if (account == null) {
      return OfficeAccount.mutalib;
    }
    if (account.id == DefaultOfficeAccountIds.ad ||
        account.displayName.toLowerCase() == 'ad') {
      return OfficeAccount.ad;
    }
    return OfficeAccount.mutalib;
  }
}
