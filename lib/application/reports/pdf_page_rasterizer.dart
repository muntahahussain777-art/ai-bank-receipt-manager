import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Renders each PDF page to a PNG so Gallery images match the PDF exactly.
abstract class PdfPageRasterizer {
  Future<List<Uint8List>> rasterizePages(
    Uint8List pdfBytes, {
    double dpi = 144,
  });
}

/// Uses the platform PDF renderer via the printing package.
class PrintingPdfPageRasterizer implements PdfPageRasterizer {
  const PrintingPdfPageRasterizer();

  @override
  Future<List<Uint8List>> rasterizePages(
    Uint8List pdfBytes, {
    double dpi = 144,
  }) async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
      pages.add(await page.toPng());
    }
    if (pages.isEmpty) {
      throw StateError('PDF produced no pages to render.');
    }
    return pages;
  }
}
