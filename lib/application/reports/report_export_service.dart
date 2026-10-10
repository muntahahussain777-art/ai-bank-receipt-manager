import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/reports/pdf_report_builder.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_query_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/xlsx_report_builder.dart';
import 'package:ai_bank_receipt_manager/data/database/database_bootstrap.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class ReportExportResult {
  const ReportExportResult({
    required this.filePath,
    required this.document,
    required this.format,
    required this.bytesWritten,
  });

  final String filePath;
  final ReportDocument document;
  final ReportFormat format;
  final int bytesWritten;
}

/// Exports reports from SQLite. Never mutates receipt entry statuses.
class ReportExportService {
  ReportExportService({
    required ReportQueryService query,
    required AppStoragePaths paths,
    PdfReportBuilder? pdfBuilder,
    XlsxReportBuilder? xlsxBuilder,
  }) : _query = query,
       _paths = paths,
       _pdf = pdfBuilder ?? PdfReportBuilder(),
       _xlsx = xlsxBuilder ?? XlsxReportBuilder();

  final ReportQueryService _query;
  final AppStoragePaths _paths;
  final PdfReportBuilder _pdf;
  final XlsxReportBuilder _xlsx;

  Future<ReportDocument> preview(ReportCriteria criteria) =>
      _query.build(criteria);

  Future<ReportExportResult> exportToFile({
    required ReportCriteria criteria,
    required ReportFormat format,
    String? targetDirectory,
  }) async {
    final document = await _query.build(criteria);
    final bytes = await _encode(document, format);
    final dir = Directory(
      targetDirectory ?? p.join(_paths.rootDirectory, 'exports'),
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final safeTitle = criteria.kind.name;
    final ext = format == ReportFormat.pdf ? 'pdf' : 'xlsx';
    final file = File(p.join(dir.path, '${safeTitle}_$stamp.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return ReportExportResult(
      filePath: file.path,
      document: document,
      format: format,
      bytesWritten: bytes.length,
    );
  }

  Future<ReportExportResult> exportAndShare({
    required ReportCriteria criteria,
    required ReportFormat format,
    String? shareText,
  }) async {
    final result = await exportToFile(criteria: criteria, format: format);
    final mime = format == ReportFormat.pdf
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(result.filePath, mimeType: mime)],
        text:
            shareText ??
            '${result.document.title} (${result.document.summary.rowCount} receipts)',
        subject: result.document.title,
      ),
    );
    return result;
  }

  Future<Uint8List> encodeBytes({
    required ReportCriteria criteria,
    required ReportFormat format,
  }) async {
    final document = await _query.build(criteria);
    return _encode(document, format);
  }

  Future<Uint8List> _encode(ReportDocument document, ReportFormat format) {
    return switch (format) {
      ReportFormat.pdf => _pdf.build(document),
      ReportFormat.xlsx => _xlsx.build(document),
    };
  }
}
