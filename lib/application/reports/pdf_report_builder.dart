import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String _plainAmount(num amount) {
  final whole = amount == amount.roundToDouble();
  return NumberFormat(whole ? '#,##0' : '#,##0.00').format(amount);
}

/// Builds landscape PDF reports from [ReportDocument] (read-only snapshot).
class PdfReportBuilder {
  Future<Uint8List> build(ReportDocument document) async {
    final pdf = pw.Document(
      title: document.title,
      author: 'AI Bank Receipt Manager',
    );
    final dateFmt = DateFormat('dd MMM yyyy');
    final dateTimeFmt = DateFormat('dd MMM yyyy HH:mm');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _header(document),
        footer: (context) => _footer(context),
        build: (context) => [
          _summaryBlock(document),
          pw.SizedBox(height: 12),
          if (document.rows.isEmpty)
            pw.Text('No receipts matched this report.')
          else
            _table(document, dateFmt, dateTimeFmt),
        ],
      ),
    );

    if (document.criteria.includeImageAppendix) {
      await _appendImages(pdf, document);
    }

    return pdf.save();
  }

  pw.Widget _header(ReportDocument document) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          document.title,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Text(document.subtitle, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Source: saved SQLite data. Export does not change entry statuses.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'AI Bank Receipt Manager',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  pw.Widget _summaryBlock(ReportDocument document) {
    final s = document.summary;
    final totalLines = <String>[
      'Rows: ${s.rowCount}',
      'Pending: ${s.pendingCount}',
      'Entered: ${s.enteredCount}',
      'Reconciliation: ${s.reconciliationCount}',
    ];
    for (final t in s.totalsByCurrency) {
      totalLines.add(
        '${t.currency} received ${_plainAmount(t.received)} / '
        'sent ${_plainAmount(t.sent)}',
      );
    }
    return pw.Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final line in totalLines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _table(
    ReportDocument document,
    DateFormat dateFmt,
    DateFormat dateTimeFmt,
  ) {
    final headers = const [
      'S#',
      'Acct date',
      'Bank date',
      'Bank',
      'Reference',
      'Sender',
      'Receiver',
      'Office',
      'Party',
      'Admin note',
      'Amount',
      'Direction',
      'Status',
      'Entered at',
      'Remarks',
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: [
        for (final row in document.rows)
          [
            '${row.serial}',
            dateFmt.format(row.accountingDate.toLocal()),
            row.bankTransactionDate == null
                ? '-'
                : dateFmt.format(row.bankTransactionDate!.toLocal()),
            row.bankName,
            row.transactionReference ?? '-',
            row.bankSender ?? '-',
            row.bankReceiver ?? '-',
            row.officeAccount,
            row.partyName,
            row.adminNote ?? '-',
            '${row.currency} ${_plainAmount(row.amount)}',
            row.direction,
            row.entryStatusLabel,
            row.enteredAt == null
                ? '-'
                : dateTimeFmt.format(row.enteredAt!.toLocal()),
            row.remarks ?? '-',
          ],
      ],
      headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
      columnWidths: {
        0: const pw.FixedColumnWidth(22),
        10: const pw.FixedColumnWidth(70),
      },
    );
  }

  Future<void> _appendImages(pw.Document pdf, ReportDocument document) async {
    for (final row in document.rows) {
      final path = row.originalImagePath;
      if (path == null || path.isEmpty) {
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      // Load one image at a time — never keep the full history in memory.
      final bytes = await file.readAsBytes();
      late final pw.MemoryImage image;
      try {
        image = pw.MemoryImage(bytes);
      } catch (_) {
        continue;
      }
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Appendix | S# ${row.serial} | ${row.bankName} | '
                '${formatAccountingDate(row.accountingDate)}',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
