import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/reports/gallery_image_saver.dart';
import 'package:ai_bank_receipt_manager/application/reports/pdf_page_rasterizer.dart';
import 'package:ai_bank_receipt_manager/application/reports/pdf_report_builder.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_query_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

enum ReportSaveMode { pdfOnly, galleryOnly, pdfAndGallery }

class ReportSaveOutcome {
  const ReportSaveOutcome({
    required this.mode,
    required this.document,
    required this.pdfRequested,
    required this.galleryRequested,
    this.pdfSaved = false,
    this.pdfCancelled = false,
    this.pdfPath,
    this.pdfFileName,
    this.pdfError,
    this.galleryPagesSaved = 0,
    this.galleryFileNames = const [],
    this.galleryError,
  });

  final ReportSaveMode mode;
  final ReportDocument document;
  final bool pdfRequested;
  final bool galleryRequested;
  final bool pdfSaved;
  final bool pdfCancelled;
  final String? pdfPath;
  final String? pdfFileName;
  final String? pdfError;
  final int galleryPagesSaved;
  final List<String> galleryFileNames;
  final String? galleryError;

  bool get bothSucceeded =>
      (!pdfRequested || pdfSaved) &&
      (!galleryRequested || (galleryError == null && galleryPagesSaved > 0));

  bool get anySucceeded => pdfSaved || galleryPagesSaved > 0;

  String summaryMessage() {
    final parts = <String>[];
    if (pdfRequested) {
      if (pdfCancelled) {
        parts.add('PDF save cancelled.');
      } else if (pdfSaved) {
        parts.add('PDF saved: ${pdfFileName ?? pdfPath}');
      } else {
        parts.add('PDF not saved${pdfError == null ? '' : ': $pdfError'}');
      }
    }
    if (galleryRequested) {
      if (galleryPagesSaved > 0 && galleryError == null) {
        parts.add('Gallery images saved: $galleryPagesSaved pages');
      } else if (galleryError != null) {
        parts.add('Gallery save failed: $galleryError');
      } else {
        parts.add('Gallery images not saved.');
      }
    }
    return parts.join('\n');
  }
}

typedef PdfDestinationPicker =
    Future<String?> Function({
      required String suggestedFileName,
      required Uint8List pdfBytes,
    });

/// Builds one frozen PDF snapshot, then saves PDF and/or Gallery PNGs.
/// Never mutates receipt statuses.
class ReportSaveService {
  ReportSaveService({
    required ReportQueryService query,
    PdfReportBuilder? pdfBuilder,
    PdfPageRasterizer? rasterizer,
    GalleryImageSaver? gallerySaver,
    PdfDestinationPicker? pdfDestinationPicker,
    this.rasterDpi = 144,
  }) : _query = query,
       _pdf = pdfBuilder ?? PdfReportBuilder(),
       _rasterizer = rasterizer ?? const PrintingPdfPageRasterizer(),
       _gallery = gallerySaver ?? const GalGalleryImageSaver(),
       _pickPdf = pdfDestinationPicker ?? _defaultPdfPicker;

  final ReportQueryService _query;
  final PdfReportBuilder _pdf;
  final PdfPageRasterizer _rasterizer;
  final GalleryImageSaver _gallery;
  final PdfDestinationPicker _pickPdf;
  final double rasterDpi;

  Future<ReportSaveOutcome> save({
    required ReportCriteria criteria,
    required ReportSaveMode mode,
  }) async {
    final document = await _query.build(criteria);
    final pdfBytes = await _pdf.build(document);
    final baseName = _baseFileName(document, criteria);

    final wantPdf =
        mode == ReportSaveMode.pdfOnly || mode == ReportSaveMode.pdfAndGallery;
    final wantGallery =
        mode == ReportSaveMode.galleryOnly ||
        mode == ReportSaveMode.pdfAndGallery;

    var pdfSaved = false;
    var pdfCancelled = false;
    String? pdfPath;
    String? pdfFileName;
    String? pdfError;

    if (wantPdf) {
      pdfFileName = '$baseName.pdf';
      try {
        final saved = await _pickPdf(
          suggestedFileName: pdfFileName,
          pdfBytes: pdfBytes,
        );
        if (saved == null) {
          pdfCancelled = true;
          // Cancelled PDF picker: do not silently save PDF elsewhere.
          // For Save Both, also skip gallery so we never claim both succeeded.
          if (mode == ReportSaveMode.pdfAndGallery) {
            return ReportSaveOutcome(
              mode: mode,
              document: document,
              pdfRequested: true,
              galleryRequested: true,
              pdfCancelled: true,
              pdfFileName: pdfFileName,
            );
          }
        } else {
          pdfSaved = true;
          pdfPath = saved;
        }
      } catch (error) {
        pdfError = '$error';
        if (mode == ReportSaveMode.pdfAndGallery) {
          return ReportSaveOutcome(
            mode: mode,
            document: document,
            pdfRequested: true,
            galleryRequested: true,
            pdfError: pdfError,
            pdfFileName: pdfFileName,
          );
        }
      }
    }

    var galleryPagesSaved = 0;
    final galleryNames = <String>[];
    String? galleryError;

    if (wantGallery) {
      try {
        final pngPages = await _rasterizer.rasterizePages(
          pdfBytes,
          dpi: rasterDpi,
        );
        final hasAccess = await _gallery.hasAccess();
        if (!hasAccess) {
          final granted = await _gallery.requestAccess();
          if (!granted) {
            throw StateError('Gallery permission was not granted.');
          }
        }
        for (var i = 0; i < pngPages.length; i++) {
          final pageName =
              '${baseName}_Page_${(i + 1).toString().padLeft(2, '0')}.png';
          await _gallery.savePng(
            bytes: pngPages[i],
            fileName: pageName.replaceAll('.png', ''),
            album: GalGalleryImageSaver.albumName,
          );
          galleryNames.add(pageName);
          galleryPagesSaved++;
        }
      } catch (error) {
        galleryError = '$error';
      }
    }

    return ReportSaveOutcome(
      mode: mode,
      document: document,
      pdfRequested: wantPdf,
      galleryRequested: wantGallery,
      pdfSaved: pdfSaved,
      pdfCancelled: pdfCancelled,
      pdfPath: pdfPath,
      pdfFileName: pdfFileName,
      pdfError: pdfError,
      galleryPagesSaved: galleryPagesSaved,
      galleryFileNames: galleryNames,
      galleryError: galleryError,
    );
  }

  static String _baseFileName(
    ReportDocument document,
    ReportCriteria criteria,
  ) {
    final dateSource =
        criteria.accountingDate ??
        criteria.dateTo ??
        criteria.dateFrom ??
        DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(dateSource);
    String label;
    if (document.rows.isNotEmpty &&
        criteria.mappedAccountId != null &&
        document.rows.first.officeAccount.trim().isNotEmpty) {
      label = document.rows.first.officeAccount;
    } else {
      label = switch (criteria.kind) {
        ReportKind.mutalib => 'Mutalib',
        ReportKind.ad => 'AD',
        _ => document.title,
      };
    }
    return '${_safeToken(label)}_Report_$date';
  }

  static String _safeToken(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'Report' : cleaned;
  }

  static Future<String?> _defaultPdfPicker({
    required String suggestedFileName,
    required Uint8List pdfBytes,
  }) async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save report PDF',
      fileName: suggestedFileName,
      bytes: pdfBytes,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      mimeType: 'application/pdf',
    );
    if (saved == null) {
      return null;
    }
    return saved.toString();
  }
}
