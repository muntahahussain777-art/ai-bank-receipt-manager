import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// Builds genuine .xlsx workbooks from [ReportDocument].
class XlsxReportBuilder {
  XlsxReportBuilder({this.injectFreezeAndFilter = true});

  final bool injectFreezeAndFilter;

  Future<Uint8List> build(ReportDocument document) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null) {
      excel.rename(defaultSheet, 'Receipts');
    }
    final sheet = excel['Receipts'];
    final dataLastRow = _writeReceiptSheet(sheet, document);

    final totals = excel['Totals'];
    _writeTotalsSheet(totals, document);

    if (document.criteria.kind == ReportKind.bankWise) {
      _writeGroupedSheet(
        excel,
        document,
        groupBy: (r) => r.bankName,
        name: 'By Bank',
      );
    }
    if (document.criteria.kind == ReportKind.customerWise) {
      _writeGroupedSheet(
        excel,
        document,
        groupBy: (r) => r.partyName,
        name: 'By Customer',
      );
    }
    if (document.criteria.kind == ReportKind.dealerWise) {
      _writeGroupedSheet(
        excel,
        document,
        groupBy: (r) => r.partyName,
        name: 'By Dealer',
      );
    }

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Failed to encode XLSX workbook.');
    }
    final bytes = Uint8List.fromList(encoded);
    if (!injectFreezeAndFilter) {
      return bytes;
    }
    return Uint8List.fromList(
      _injectFreezeAndFilter(
        bytes,
        filterLastRow: dataLastRow < 1 ? 1 : dataLastRow,
        filterLastCol: 'P',
      ),
    );
  }

  /// Returns 1-based last data row index (header is row 1).
  int _writeReceiptSheet(Sheet sheet, ReportDocument document) {
    final headers = [
      'Serial',
      'Accounting date',
      'Bank transaction date',
      'Bank name',
      'Transaction reference',
      'Bank sender',
      'Bank receiver',
      'Office account',
      'Customer/dealer',
      'Admin note',
      'Amount',
      'Currency',
      'Incoming/outgoing',
      'Entry status',
      'Entered timestamp',
      'Remarks',
    ];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#D9E2F3'),
      horizontalAlign: HorizontalAlign.Center,
    );

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    final dateFmt = DateFormat('yyyy-MM-dd');
    final dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

    for (var i = 0; i < document.rows.length; i++) {
      final row = document.rows[i];
      final r = i + 1;
      _text(sheet, 0, r, '${row.serial}');
      _text(sheet, 1, r, dateFmt.format(row.accountingDate.toLocal()));
      _text(
        sheet,
        2,
        r,
        row.bankTransactionDate == null
            ? ''
            : dateFmt.format(row.bankTransactionDate!.toLocal()),
      );
      _text(sheet, 3, r, row.bankName);
      _text(sheet, 4, r, row.transactionReference ?? '');
      _text(sheet, 5, r, row.bankSender ?? '');
      _text(sheet, 6, r, row.bankReceiver ?? '');
      _text(sheet, 7, r, row.officeAccount);
      _text(sheet, 8, r, row.partyName);
      _text(sheet, 9, r, row.adminNote ?? '');
      final amountCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r),
      );
      amountCell.value = DoubleCellValue(row.amount);
      amountCell.cellStyle = CellStyle(numberFormat: NumFormat.standard_2);
      _text(sheet, 11, r, row.currency);
      _text(sheet, 12, r, row.direction);
      _text(sheet, 13, r, row.entryStatusLabel);
      _text(
        sheet,
        14,
        r,
        row.enteredAt == null
            ? ''
            : dateTimeFmt.format(row.enteredAt!.toLocal()),
      );
      _text(sheet, 15, r, row.remarks ?? '');
    }

    final totalsRow = document.rows.length + 2;
    _text(sheet, 0, totalsRow, 'TOTALS');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalsRow))
        .cellStyle = CellStyle(
      bold: true,
    );
    var offset = 1;
    for (final t in document.summary.totalsByCurrency) {
      _text(sheet, 0, totalsRow + offset, '${t.currency} received');
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: 10,
              rowIndex: totalsRow + offset,
            ),
          )
          .value = DoubleCellValue(
        t.received,
      );
      offset += 1;
      _text(sheet, 0, totalsRow + offset, '${t.currency} sent');
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: 10,
              rowIndex: totalsRow + offset,
            ),
          )
          .value = DoubleCellValue(
        t.sent,
      );
      offset += 1;
    }
    _text(
      sheet,
      0,
      totalsRow + offset,
      'Pending ${document.summary.pendingCount} | '
      'Entered ${document.summary.enteredCount} | '
      'Reconciliation ${document.summary.reconciliationCount}',
    );

    for (var c = 0; c < headers.length; c++) {
      sheet.setColumnAutoFit(c);
    }
    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(10, 14);
    sheet.setColumnWidth(13, 18);

    return document.rows.isEmpty ? 1 : document.rows.length + 1;
  }

  void _writeTotalsSheet(Sheet sheet, ReportDocument document) {
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
    );
    final headers = [
      'Currency',
      'Received',
      'Sent',
      'Pending',
      'Entered',
      'Reconciliation',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }
    if (document.summary.totalsByCurrency.isEmpty) {
      _text(sheet, 0, 1, 'PKR');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value = DoubleCellValue(
        0,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1))
          .value = DoubleCellValue(
        0,
      );
    } else {
      for (var i = 0; i < document.summary.totalsByCurrency.length; i++) {
        final t = document.summary.totalsByCurrency[i];
        final r = i + 1;
        _text(sheet, 0, r, t.currency);
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
            .value = DoubleCellValue(
          t.received,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
            .value = DoubleCellValue(
          t.sent,
        );
      }
    }
    final metaRow = document.summary.totalsByCurrency.length + 2;
    _text(sheet, 0, metaRow, 'Counts');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: metaRow))
        .value = IntCellValue(
      document.summary.pendingCount,
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: metaRow))
        .value = IntCellValue(
      document.summary.enteredCount,
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: metaRow))
        .value = IntCellValue(
      document.summary.reconciliationCount,
    );
  }

  void _writeGroupedSheet(
    Excel excel,
    ReportDocument document, {
    required String Function(ReportRow) groupBy,
    required String name,
  }) {
    final sheet = excel[name];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#FFF2CC'),
    );
    final headers = ['Group', 'Count', 'Received', 'Sent'];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    final groups = <String, List<ReportRow>>{};
    for (final row in document.rows) {
      groups.putIfAbsent(groupBy(row), () => []).add(row);
    }
    final keys = groups.keys.toList()..sort();
    var r = 1;
    for (final key in keys) {
      final list = groups[key]!;
      var received = 0.0;
      var sent = 0.0;
      for (final row in list) {
        if (row.direction == 'Outgoing') {
          sent += row.amount;
        } else if (row.direction == 'Incoming') {
          received += row.amount;
        }
      }
      _text(sheet, 0, r, key);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
          .value = IntCellValue(
        list.length,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r))
          .value = DoubleCellValue(
        received,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r))
          .value = DoubleCellValue(
        sent,
      );
      r += 1;
    }
  }

  void _text(Sheet sheet, int column, int row, String value) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .value = TextCellValue(
      value,
    );
  }

  /// Injects frozen header row + autoFilter into worksheet XML (Receipts first).
  List<int> _injectFreezeAndFilter(
    Uint8List xlsxBytes, {
    required int filterLastRow,
    required String filterLastCol,
  }) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final out = Archive();
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      var content = List<int>.from(file.content as List<int>);
      final isSheet =
          file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml');
      if (isSheet) {
        var xml = utf8.decode(content);
        if (!xml.contains('state="frozen"')) {
          if (xml.contains('<sheetViews>')) {
            xml = xml.replaceFirst(
              '<sheetViews>',
              '<sheetViews><sheetView workbookViewId="0">'
                  '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
                  'state="frozen"/></sheetView>',
            );
          } else if (xml.contains('<dimension ')) {
            xml = xml.replaceFirst(
              '<dimension ',
              '<sheetViews><sheetView workbookViewId="0">'
                  '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
                  'state="frozen"/></sheetView></sheetViews><dimension ',
            );
          } else {
            xml = xml.replaceFirst(
              '<sheetData',
              '<sheetViews><sheetView workbookViewId="0">'
                  '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
                  'state="frozen"/></sheetView></sheetViews><sheetData',
            );
          }
        }
        if (!xml.contains('autoFilter') && file.name.contains('sheet1')) {
          final ref = 'A1:$filterLastCol$filterLastRow';
          xml = xml.replaceFirst(
            '</worksheet>',
            '<autoFilter ref="$ref"/></worksheet>',
          );
        }
        content = utf8.encode(xml);
      }
      out.addFile(ArchiveFile(file.name, content.length, content));
    }
    final encoded = ZipEncoder().encode(out);
    return encoded ?? xlsxBytes;
  }
}
