import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/desk/receipt_entry_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/pdf_report_builder.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_export_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_query_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/xlsx_report_builder.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late ReceiptRepository receipts;
  late ReceiptEntryService entry;
  late ReportQueryService query;
  late ReportExportService export;

  setUp(() async {
    harness = await TestDbHarness.create();
    receipts = harness.receipts;
    entry = ReceiptEntryService(receipts);
    query = ReportQueryService(
      receipts: receipts,
      offices: OfficeAccountRepository(harness.database),
      customers: CustomerRepository(harness.database),
      dealers: DealerRepository(harness.database),
    );
    export = ReportExportService(query: query, paths: harness.paths);
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<void> importCount(
    int count, {
    required String prefix,
    DateTime? date,
    DbReceiptType type = DbReceiptType.received,
    double startAmount = 1000,
  }) async {
    await receipts.appendImport(
      accountingDate: date ?? DateTime(2026, 10, 10),
      source: 'phase8',
      drafts: [
        for (var i = 0; i < count; i++)
          harness.draft(
            transactionId: '${prefix}_$i',
            amount: startAmount + i,
            type: type,
          ),
      ],
    );
  }

  test('empty report exports valid PDF and XLSX', () async {
    final doc = await query.build(
      ReportCriteria(
        kind: ReportKind.dailyReceipt,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(doc.rows, isEmpty);
    expect(doc.summary.rowCount, 0);

    final pdf = await PdfReportBuilder().build(doc);
    expect(pdf.length, greaterThan(100));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    final xlsx = await XlsxReportBuilder().build(doc);
    expect(_isZip(xlsx), isTrue);
    final decoded = Excel.decodeBytes(xlsx);
    expect(decoded.tables.keys, contains('Receipts'));
  });

  test(
    '25 receipt report regenerates after evening import without status reset',
    () async {
      await importCount(20, prefix: 'MID');
      final day = DateTime(2026, 10, 10);
      final rows = await receipts.listByAccountingDate(day);
      for (var i = 0; i < 12; i++) {
        await entry.markEntered(id: rows[i].id, enteredBy: 'clerk');
      }

      final first = await query.build(
        ReportCriteria(kind: ReportKind.dailyReceipt, accountingDate: day),
      );
      expect(first.summary.rowCount, 20);
      expect(first.summary.enteredCount, 12);
      expect(first.summary.pendingCount, 8);

      final firstExport = await export.exportToFile(
        criteria: ReportCriteria(
          kind: ReportKind.dailyReceipt,
          accountingDate: day,
        ),
        format: ReportFormat.xlsx,
      );
      expect(File(firstExport.filePath).existsSync(), isTrue);

      await importCount(5, prefix: 'EVE', startAmount: 5000);

      final second = await query.build(
        ReportCriteria(kind: ReportKind.dailyReceipt, accountingDate: day),
      );
      expect(second.summary.rowCount, 25);
      expect(second.summary.enteredCount, 12);
      expect(second.summary.pendingCount, 13);

      // Export must not change statuses.
      final after = await receipts.listByAccountingDate(day);
      expect(
        after.where((r) => r.entryStatus == DbEntryStatus.entered).length,
        12,
      );
      expect(
        after.every(
          (r) =>
              r.reviewStatus != DbReviewStatus.needsReconciliation ||
              r.entryStatus == DbEntryStatus.entered,
        ),
        isTrue,
      );
    },
  );

  test('historical, pending-only, and reconciliation exports', () async {
    await importCount(3, prefix: 'HIST', date: DateTime(2026, 10, 8));
    await importCount(4, prefix: 'TODAY');
    final today = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    await entry.markEntered(id: today.first.id, enteredBy: 'clerk');
    await entry.applyFinancialEdit(
      id: today.first.id,
      newAmount: 42,
      changedBy: 'clerk',
      userConfirmedReconciliation: true,
    );

    final historical = await query.build(
      ReportCriteria(
        kind: ReportKind.dateRange,
        dateFrom: DateTime(2026, 10, 8),
        dateTo: DateTime(2026, 10, 8),
      ),
    );
    expect(historical.summary.rowCount, 3);

    final pending = await query.build(
      ReportCriteria(
        kind: ReportKind.pendingEntries,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(pending.rows.every((r) => r.entryStatusLabel == 'Pending'), isTrue);
    expect(pending.summary.rowCount, 3);

    final recon = await query.build(
      ReportCriteria(
        kind: ReportKind.reconciliationRequired,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(recon.summary.rowCount, 1);
    expect(recon.rows.single.entryStatusLabel, 'Needs Reconciliation');

    final entered = await query.build(
      ReportCriteria(
        kind: ReportKind.enteredEntries,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(entered.summary.rowCount, 0);
  });

  test('PDF pagination for large report and XLSX numeric amounts', () async {
    await importCount(80, prefix: 'BIG', startAmount: 100.25);
    final doc = await query.build(
      ReportCriteria(
        kind: ReportKind.dailyReceipt,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(doc.summary.rowCount, 80);
    expect(doc.rows.map((r) => r.amount), contains(100.25));
    expect(
      doc.rows.map((r) => r.amount).reduce((a, b) => a < b ? a : b),
      100.25,
    );

    final pdf = await PdfReportBuilder().build(doc);
    expect(pdf.length, greaterThan(5000));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    final plainXlsx = await XlsxReportBuilder(
      injectFreezeAndFilter: false,
    ).build(doc);
    expect(_isZip(plainXlsx), isTrue);
    final book = Excel.decodeBytes(plainXlsx);
    expect(book.tables.containsKey('Receipts'), isTrue);
    final receiptsSheet = book.tables['Receipts'];
    expect(receiptsSheet, isNotNull);
    if (receiptsSheet == null) {
      return;
    }
    var amountCol = -1;
    for (var c = 0; c < 20; c++) {
      final header = receiptsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value;
      if ('$header' == 'Amount') {
        amountCol = c;
        break;
      }
    }
    expect(amountCol, greaterThanOrEqualTo(0));
    final amounts = <double>[];
    for (var r = 1; r <= doc.rows.length; r++) {
      final amountCell = receiptsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: amountCol, rowIndex: r))
          .value;
      final amount = switch (amountCell) {
        DoubleCellValue(:final value) => value,
        IntCellValue(:final value) => value.toDouble(),
        _ => null,
      };
      if (amount != null) {
        amounts.add(amount);
      }
    }
    expect(amounts.length, doc.rows.length);
    final expectedSum = doc.rows.fold<double>(0, (s, r) => s + r.amount);
    final actualSum = amounts.fold<double>(0, (s, v) => s + v);
    expect(actualSum, closeTo(expectedSum, 0.001));
    expect(amounts, contains(100.25));

    final styledXlsx = await XlsxReportBuilder().build(doc);
    final archive = ZipDecoder().decodeBytes(styledXlsx);
    final sheetXmls = [
      for (final f in archive.files)
        if (f.isFile &&
            f.name.startsWith('xl/worksheets/sheet') &&
            f.name.endsWith('.xml'))
          utf8.decode(f.content as List<int>),
    ];
    expect(sheetXmls.any((xml) => xml.contains('state="frozen"')), isTrue);
    expect(sheetXmls.any((xml) => xml.contains('autoFilter')), isTrue);
  });

  test('Mutalib and AD office reports and bank-wise totals', () async {
    await receipts.appendImport(
      accountingDate: DateTime(2026, 10, 10),
      source: 'office',
      drafts: [
        harness.draft(transactionId: 'M1', amount: 1000),
        harness.draft(transactionId: 'A1', amount: 2000),
        harness.draft(
          transactionId: 'S1',
          amount: 300,
          type: DbReceiptType.sent,
        ),
      ],
    );
    final list = await receipts.listByAccountingDate(DateTime(2026, 10, 10));
    await receipts.updateReceipt(
      updated: list[0].copyWith(
        mappedAccountId: DefaultOfficeAccountIds.mutalib,
      ),
    );
    await receipts.updateReceipt(
      updated: list[1].copyWith(mappedAccountId: DefaultOfficeAccountIds.ad),
    );
    await receipts.updateReceipt(
      updated: list[2].copyWith(
        mappedAccountId: DefaultOfficeAccountIds.mutalib,
        receiptType: DbReceiptType.sent,
      ),
    );

    final mutalib = await query.build(
      ReportCriteria(
        kind: ReportKind.mutalib,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(mutalib.summary.rowCount, 2);
    expect(mutalib.summary.totalsByCurrency.single.received, 1000);
    expect(mutalib.summary.totalsByCurrency.single.sent, 300);

    final ad = await query.build(
      ReportCriteria(
        kind: ReportKind.ad,
        accountingDate: DateTime(2026, 10, 10),
      ),
    );
    expect(ad.summary.rowCount, 1);

    final bank = await query.build(
      ReportCriteria(
        kind: ReportKind.bankWise,
        accountingDate: DateTime(2026, 10, 10),
        bankName: 'HBL',
      ),
    );
    expect(bank.summary.rowCount, 3);
    // Received and sent kept separate — no double-count into one bucket.
    final totals = bank.summary.totalsByCurrency.single;
    expect(totals.received, 3000);
    expect(totals.sent, 300);
  });

  test('export never mutates entry statuses', () async {
    await importCount(2, prefix: 'SAFE');
    final row = (await receipts.listByAccountingDate(
      DateTime(2026, 10, 10),
    )).first;
    await entry.markEntered(id: row.id, enteredBy: 'clerk');
    final before = await receipts.getById(row.id);

    await export.exportToFile(
      criteria: ReportCriteria(kind: ReportKind.fullHistory),
      format: ReportFormat.pdf,
    );
    await export.encodeBytes(
      criteria: ReportCriteria(
        kind: ReportKind.enteredEntries,
        accountingDate: DateTime(2026, 10, 10),
      ),
      format: ReportFormat.xlsx,
    );

    final after = await receipts.getById(row.id);
    expect(after!.entryStatus, before!.entryStatus);
    expect(after.enteredAt, before.enteredAt);
    expect(after.reviewStatus, before.reviewStatus);
    expect(after.amount, before.amount);
  });
}

bool _isZip(Uint8List bytes) {
  return bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
}
