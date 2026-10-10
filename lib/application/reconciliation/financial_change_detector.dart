import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';

/// Proposed financial patch for an existing receipt.
class ReceiptFinancialPatch {
  const ReceiptFinancialPatch({
    this.amount,
    this.accountingDate,
    this.receiptType,
    this.mappedAccountId,
    this.customerId,
    this.dealerId,
    this.transactionId,
    this.adminMessage,
    this.notes,
    this.partyDisplayName,
    this.clearCustomerId = false,
    this.clearDealerId = false,
    this.clearMappedAccountId = false,
    this.clearTransactionId = false,
  });

  final double? amount;
  final DateTime? accountingDate;
  final DbReceiptType? receiptType;
  final String? mappedAccountId;
  final String? customerId;
  final String? dealerId;
  final String? transactionId;
  final String? adminMessage;
  final String? notes;
  final String? partyDisplayName;
  final bool clearCustomerId;
  final bool clearDealerId;
  final bool clearMappedAccountId;
  final bool clearTransactionId;
}

/// Detects financial fields that require WinForms reconciliation after Entered.
abstract final class FinancialChangeDetector {
  static List<FinancialFieldDiff> detect(
    ReceiptRecord existing,
    ReceiptFinancialPatch patch,
  ) {
    final proposed = applyPatch(existing, patch);
    final diffs = <FinancialFieldDiff>[];

    void track(String field, String label, Object? oldValue, Object? newValue) {
      final oldText = oldValue?.toString();
      final newText = newValue?.toString();
      if (oldText == newText) {
        return;
      }
      diffs.add(
        FinancialFieldDiff(
          field: field,
          label: label,
          oldValue: oldText,
          newValue: newText,
        ),
      );
    }

    track('amount', 'Amount', existing.amount, proposed.amount);
    track(
      'accounting_date',
      'Accounting date',
      encodeDateOnly(existing.accountingDate),
      encodeDateOnly(proposed.accountingDate),
    );
    track(
      'receipt_type',
      'Transaction direction',
      existing.receiptType.storageValue,
      proposed.receiptType.storageValue,
    );
    track(
      'mapped_account_id',
      'Office account',
      existing.mappedAccountId,
      proposed.mappedAccountId,
    );
    track('customer_id', 'Customer', existing.customerId, proposed.customerId);
    track('dealer_id', 'Dealer', existing.dealerId, proposed.dealerId);
    track(
      'transaction_id',
      'Transaction reference',
      existing.transactionId,
      proposed.transactionId,
    );

    return diffs;
  }

  /// True when only non-financial fields (notes / admin message) change.
  static bool isFinancialChange(
    ReceiptRecord existing,
    ReceiptFinancialPatch patch,
  ) {
    return detect(existing, patch).isNotEmpty;
  }

  static ReceiptRecord applyPatch(
    ReceiptRecord existing,
    ReceiptFinancialPatch patch,
  ) {
    return existing.copyWith(
      amount: patch.amount ?? existing.amount,
      accountingDate: patch.accountingDate == null
          ? existing.accountingDate
          : dateOnlyUtc(patch.accountingDate!),
      receiptType: patch.receiptType ?? existing.receiptType,
      mappedAccountId: patch.mappedAccountId,
      customerId: patch.customerId,
      dealerId: patch.dealerId,
      transactionId: patch.transactionId,
      adminMessage: patch.adminMessage ?? existing.adminMessage,
      notes: patch.notes ?? existing.notes,
      clearMappedAccountId: patch.clearMappedAccountId,
      clearCustomerId: patch.clearCustomerId,
      clearDealerId: patch.clearDealerId,
      clearTransactionId: patch.clearTransactionId,
    );
  }
}
