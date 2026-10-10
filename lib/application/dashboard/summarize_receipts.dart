import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/domain/entities/dashboard_summary.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_flow.dart';

/// Summarize desk receipts for any dynamic list of office accounts.
DashboardSummary summarizeReceiptsForAccounts({
  required List<Receipt> receipts,
  required List<OfficeAccountRecord> accounts,
  Map<String, String>? previewAccountIdByOfficeKey,
  Map<String, String>? primaryAliasByAccountId,
}) {
  var received = 0.0;
  var sent = 0.0;
  var pending = 0;
  var entered = 0;
  var reconciliation = 0;

  final receivedBy = <String, double>{};
  final sentBy = <String, double>{};
  final countBy = <String, int>{};

  for (final account in accounts) {
    receivedBy[account.id] = 0;
    sentBy[account.id] = 0;
    countBy[account.id] = 0;
  }

  for (final receipt in receipts) {
    final isReceived = receipt.officeFlow == OfficeFlow.customerToOffice;
    if (isReceived) {
      received += receipt.amount;
    } else {
      sent += receipt.amount;
    }

    switch (receipt.status) {
      case EntryStatus.pending:
        pending += 1;
      case EntryStatus.entered:
        entered += 1;
      case EntryStatus.needsReconciliation:
        reconciliation += 1;
    }

    final accountId =
        previewAccountIdByOfficeKey?[receipt.officeAccount.name] ??
        _matchAccountId(receipt, accounts);
    if (accountId == null) {
      continue;
    }
    countBy[accountId] = (countBy[accountId] ?? 0) + 1;
    if (isReceived) {
      receivedBy[accountId] = (receivedBy[accountId] ?? 0) + receipt.amount;
    } else {
      sentBy[accountId] = (sentBy[accountId] ?? 0) + receipt.amount;
    }
  }

  return DashboardSummary(
    totalReceived: received,
    totalSent: sent,
    pendingCount: pending,
    enteredCount: entered,
    reconciliationCount: reconciliation,
    accountActivities: [
      for (final account in accounts)
        OfficeAccountActivity(
          account: account,
          received: receivedBy[account.id] ?? 0,
          sent: sentBy[account.id] ?? 0,
          count: countBy[account.id] ?? 0,
          primaryAlias: primaryAliasByAccountId?[account.id],
        ),
    ],
  );
}

String? _matchAccountId(Receipt receipt, List<OfficeAccountRecord> accounts) {
  final needle = switch (receipt.officeAccount) {
    OfficeAccount.mutalib => 'mutalib',
    OfficeAccount.ad => 'ad',
  };
  for (final account in accounts) {
    if (account.displayName.toLowerCase() == needle ||
        account.officeKey?.toLowerCase() == needle) {
      return account.id;
    }
  }
  return null;
}

/// @Deprecated Use [summarizeReceiptsForAccounts] with dynamic office accounts.
DashboardSummary summarizeReceipts(List<Receipt> receipts) {
  return summarizeReceiptsForAccounts(receipts: receipts, accounts: const []);
}
