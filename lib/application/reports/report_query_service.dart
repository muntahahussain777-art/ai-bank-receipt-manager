import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/data/database/mappers.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:intl/intl.dart';

/// Builds report documents from saved SQLite rows only.
/// Export paths must never call markEntered / update status.
class ReportQueryService {
  ReportQueryService({
    required ReceiptRepository receipts,
    required OfficeAccountRepository offices,
    required CustomerRepository customers,
    required DealerRepository dealers,
  }) : _receipts = receipts,
       _offices = offices,
       _customers = customers,
       _dealers = dealers;

  final ReceiptRepository _receipts;
  final OfficeAccountRepository _offices;
  final CustomerRepository _customers;
  final DealerRepository _dealers;

  Future<ReportDocument> build(ReportCriteria criteria) async {
    final filter = _toListFilter(criteria);
    final records = await _receipts.listFiltered(filter);

    // Deduplicate by receipt id (safety against join-style double counts).
    final unique = <String, ReceiptRecord>{};
    for (final record in records) {
      unique[record.id] = record;
    }
    var rows = unique.values.toList()
      ..sort((a, b) {
        final byDate = a.accountingDate.compareTo(b.accountingDate);
        if (byDate != 0) {
          return byDate;
        }
        return a.importedAt.compareTo(b.importedAt);
      });

    rows = _applyKindPostFilter(criteria, rows);

    final offices = await _offices.list(
      includeInactive: true,
      includeArchived: true,
    );
    final officeById = {for (final o in offices) o.id: o};
    final customers = await _customers.list(includeArchived: true);
    final customerById = {for (final c in customers) c.id: c};
    final dealers = await _dealers.list(includeArchived: true);
    final dealerById = {for (final d in dealers) d.id: d};

    final reportRows = <ReportRow>[];
    var serial = 1;
    for (final record in rows) {
      final office = record.mappedAccountId == null
          ? null
          : officeById[record.mappedAccountId!];
      final customer = record.customerId == null
          ? null
          : customerById[record.customerId!];
      final dealer = record.dealerId == null
          ? null
          : dealerById[record.dealerId!];
      final party =
          customer?.name ??
          dealer?.name ??
          (record.adminMessage?.trim().isNotEmpty == true
              ? record.adminMessage!.trim()
              : 'Unassigned');

      reportRows.add(
        ReportRow(
          serial: serial++,
          receiptId: record.id,
          accountingDate: record.accountingDate,
          bankTransactionDate: record.transactionDateTime,
          bankName: record.bankName,
          transactionReference: record.transactionId,
          bankSender: record.bankSenderName,
          bankReceiver: record.bankReceiverName,
          officeAccount: office?.displayName ?? 'Unassigned',
          partyName: party,
          adminNote: record.adminMessage,
          amount: record.amount,
          currency: record.currency,
          direction: composeDirectionLabel(record.receiptType),
          entryStatusLabel: composeReportStatusLabel(
            entryStatus: record.entryStatus,
            reviewStatus: record.reviewStatus,
          ),
          enteredAt: record.enteredAt,
          remarks: record.notes,
          originalImagePath: record.originalImagePath,
        ),
      );
    }

    return ReportDocument(
      title: criteria.kind.title,
      subtitle: _subtitle(criteria),
      generatedAt: DateTime.now().toUtc(),
      criteria: criteria,
      rows: reportRows,
      summary: _summarize(rows),
    );
  }

  ReceiptListFilter _toListFilter(ReportCriteria criteria) {
    DateTime? accountingDate;
    DateTime? from = criteria.dateFrom;
    DateTime? to = criteria.dateTo;
    DbEntryStatus? entryStatus;
    DbReviewStatus? reviewStatus;
    String? bankName = criteria.bankName;
    // Explicit office UUID from the UI always wins over report-kind defaults.
    String? mappedAccountId = criteria.mappedAccountId;
    String? customerId = criteria.customerId;
    String? dealerId = criteria.dealerId;
    final explicitOfficeId = criteria.mappedAccountId;

    switch (criteria.kind) {
      case ReportKind.dailyReceipt:
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate ?? dateOnly(DateTime.now());
        }
      case ReportKind.dateRange:
        from = criteria.dateFrom;
        to = criteria.dateTo;
      case ReportKind.mutalib:
        // Prefer explicit UUID from the report screen; fall back to seed id.
        mappedAccountId =
            criteria.mappedAccountId ?? DefaultOfficeAccountIds.mutalib;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.ad:
        mappedAccountId =
            criteria.mappedAccountId ?? DefaultOfficeAccountIds.ad;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.bankWise:
        bankName = criteria.bankName;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.customerWise:
        customerId = criteria.customerId;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.dealerWise:
        dealerId = criteria.dealerId;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.pendingEntries:
        entryStatus = DbEntryStatus.pending;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.enteredEntries:
        entryStatus = DbEntryStatus.entered;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.reconciliationRequired:
        reviewStatus = DbReviewStatus.needsReconciliation;
        if (criteria.dateFrom != null || criteria.dateTo != null) {
          from = criteria.dateFrom;
          to = criteria.dateTo;
        } else {
          accountingDate = criteria.accountingDate;
        }
      case ReportKind.fullHistory:
        from = criteria.dateFrom;
        to = criteria.dateTo;
    }

    if (explicitOfficeId != null && explicitOfficeId.isNotEmpty) {
      mappedAccountId = explicitOfficeId;
    }

    return ReceiptListFilter(
      accountingDate: from == null && to == null ? accountingDate : null,
      accountingDateFrom: from == null ? null : dateOnlyUtc(from),
      accountingDateTo: to == null ? null : dateOnlyUtc(to),
      bankName: bankName,
      mappedAccountId: mappedAccountId,
      customerId: customerId,
      dealerId: dealerId,
      entryStatus: entryStatus,
      reviewStatus: reviewStatus,
    );
  }

  List<ReceiptRecord> _applyKindPostFilter(
    ReportCriteria criteria,
    List<ReceiptRecord> rows,
  ) {
    switch (criteria.kind) {
      case ReportKind.pendingEntries:
        return [
          for (final r in rows)
            if (r.entryStatus == DbEntryStatus.pending &&
                r.reviewStatus != DbReviewStatus.needsReconciliation)
              r,
        ];
      case ReportKind.enteredEntries:
        return [
          for (final r in rows)
            if (r.entryStatus == DbEntryStatus.entered &&
                r.reviewStatus != DbReviewStatus.needsReconciliation)
              r,
        ];
      case ReportKind.reconciliationRequired:
        return [
          for (final r in rows)
            if (r.reviewStatus == DbReviewStatus.needsReconciliation) r,
        ];
      default:
        return rows;
    }
  }

  ReportSummary _summarize(List<ReceiptRecord> rows) {
    var pending = 0;
    var entered = 0;
    var recon = 0;
    final received = <String, double>{};
    final sent = <String, double>{};
    final seen = <String>{};

    for (final row in rows) {
      if (!seen.add(row.id)) {
        continue;
      }
      final currency = row.currency.trim().isEmpty ? 'PKR' : row.currency;
      if (row.reviewStatus == DbReviewStatus.needsReconciliation) {
        recon += 1;
      } else if (row.entryStatus == DbEntryStatus.entered) {
        entered += 1;
      } else {
        pending += 1;
      }
      if (row.receiptType == DbReceiptType.sent) {
        sent[currency] = (sent[currency] ?? 0) + row.amount;
      } else if (row.receiptType == DbReceiptType.received) {
        received[currency] = (received[currency] ?? 0) + row.amount;
      }
      // Unknown direction is excluded from received/sent totals to avoid
      // mis-attribution; it still appears as a row.
    }

    final currencies = {...received.keys, ...sent.keys}.toList()..sort();
    return ReportSummary(
      rowCount: seen.length,
      pendingCount: pending,
      enteredCount: entered,
      reconciliationCount: recon,
      totalsByCurrency: [
        for (final c in currencies)
          CurrencyDirectionTotals(
            currency: c,
            received: received[c] ?? 0,
            sent: sent[c] ?? 0,
          ),
      ],
    );
  }

  String _subtitle(ReportCriteria criteria) {
    final parts = <String>[];
    if (criteria.kind == ReportKind.dailyReceipt &&
        criteria.accountingDate != null) {
      parts.add(
        'Accounting date ${formatAccountingDate(criteria.accountingDate!)}',
      );
    }
    if (criteria.dateFrom != null || criteria.dateTo != null) {
      final from = criteria.dateFrom == null
          ? '…'
          : formatAccountingDate(criteria.dateFrom!);
      final to = criteria.dateTo == null
          ? '…'
          : formatAccountingDate(criteria.dateTo!);
      parts.add('Range $from - $to');
    }
    if (criteria.bankName != null && criteria.bankName!.isNotEmpty) {
      parts.add('Bank ${criteria.bankName}');
    }
    if (parts.isEmpty) {
      parts.add('All matching saved receipts');
    }
    parts.add(
      'Generated ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.now())}',
    );
    return parts.join(' | ');
  }
}
