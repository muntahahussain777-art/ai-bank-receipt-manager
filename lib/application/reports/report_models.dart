import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';

/// All Phase 8 report kinds. Queries always read SQLite; never mutate statuses.
enum ReportKind {
  dailyReceipt,
  dateRange,
  mutalib,
  ad,
  bankWise,
  customerWise,
  dealerWise,
  pendingEntries,
  enteredEntries,
  reconciliationRequired,
  fullHistory,
}

extension ReportKindLabel on ReportKind {
  String get title => switch (this) {
    ReportKind.dailyReceipt => 'Daily Receipt Report',
    ReportKind.dateRange => 'Date Range Report',
    ReportKind.mutalib => 'Mutalib Report',
    ReportKind.ad => 'AD Report',
    ReportKind.bankWise => 'Bank-wise Report',
    ReportKind.customerWise => 'Customer-wise Report',
    ReportKind.dealerWise => 'Dealer-wise Report',
    ReportKind.pendingEntries => 'Pending Entries Report',
    ReportKind.enteredEntries => 'Entered Entries Report',
    ReportKind.reconciliationRequired => 'Reconciliation Required Report',
    ReportKind.fullHistory => 'Full Transaction History',
  };
}

enum ReportFormat { pdf, xlsx }

class ReportCriteria {
  const ReportCriteria({
    required this.kind,
    this.accountingDate,
    this.dateFrom,
    this.dateTo,
    this.bankName,
    this.mappedAccountId,
    this.customerId,
    this.dealerId,
    this.includeImageAppendix = false,
  });

  final ReportKind kind;
  final DateTime? accountingDate;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? bankName;
  final String? mappedAccountId;
  final String? customerId;
  final String? dealerId;
  final bool includeImageAppendix;
}

class ReportRow {
  const ReportRow({
    required this.serial,
    required this.receiptId,
    required this.accountingDate,
    this.bankTransactionDate,
    required this.bankName,
    this.transactionReference,
    this.bankSender,
    this.bankReceiver,
    required this.officeAccount,
    required this.partyName,
    this.adminNote,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.entryStatusLabel,
    this.enteredAt,
    this.remarks,
    this.originalImagePath,
  });

  final int serial;
  final String receiptId;
  final DateTime accountingDate;
  final DateTime? bankTransactionDate;
  final String bankName;
  final String? transactionReference;
  final String? bankSender;
  final String? bankReceiver;
  final String officeAccount;
  final String partyName;
  final String? adminNote;
  final double amount;
  final String currency;
  final String direction;
  final String entryStatusLabel;
  final DateTime? enteredAt;
  final String? remarks;
  final String? originalImagePath;
}

/// Totals keyed by currency, separated by bank direction (never mixed).
class CurrencyDirectionTotals {
  const CurrencyDirectionTotals({
    required this.currency,
    required this.received,
    required this.sent,
  });

  final String currency;
  final double received;
  final double sent;
}

class ReportSummary {
  const ReportSummary({
    required this.rowCount,
    required this.pendingCount,
    required this.enteredCount,
    required this.reconciliationCount,
    required this.totalsByCurrency,
  });

  final int rowCount;
  final int pendingCount;
  final int enteredCount;
  final int reconciliationCount;
  final List<CurrencyDirectionTotals> totalsByCurrency;
}

class ReportDocument {
  const ReportDocument({
    required this.title,
    required this.subtitle,
    required this.generatedAt,
    required this.criteria,
    required this.rows,
    required this.summary,
  });

  final String title;
  final String subtitle;
  final DateTime generatedAt;
  final ReportCriteria criteria;
  final List<ReportRow> rows;
  final ReportSummary summary;
}

/// Compose desk status label from stored entry + review fields.
String composeReportStatusLabel({
  required DbEntryStatus entryStatus,
  required DbReviewStatus reviewStatus,
}) {
  if (reviewStatus == DbReviewStatus.needsReconciliation) {
    return 'Needs Reconciliation';
  }
  return switch (entryStatus) {
    DbEntryStatus.entered => 'Entered',
    DbEntryStatus.pending => 'Pending',
  };
}

String composeDirectionLabel(DbReceiptType type) {
  return switch (type) {
    DbReceiptType.received => 'Incoming',
    DbReceiptType.sent => 'Outgoing',
    DbReceiptType.unknown => 'Unknown',
  };
}
