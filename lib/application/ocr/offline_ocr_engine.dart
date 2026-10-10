import 'dart:typed_data';

/// Free on-device OCR. Implementations must not call paid cloud APIs.
abstract class OfflineOcrEngine {
  Future<OfflineOcrResult> recognize(Uint8List imageBytes, {String? mimeType});
}

class OfflineOcrResult {
  const OfflineOcrResult({
    required this.fullText,
    this.lines = const [],
    this.engineName = 'Offline OCR',
  });

  final String fullText;
  final List<OfflineOcrLine> lines;
  final String engineName;
}

class OfflineOcrLine {
  const OfflineOcrLine({required this.text, this.confidence});

  final String text;
  final double? confidence;
}

/// Used in unit tests and when ML Kit is unavailable on the host.
class FakeOfflineOcrEngine implements OfflineOcrEngine {
  FakeOfflineOcrEngine([this.fixedText]);

  final String? fixedText;

  @override
  Future<OfflineOcrResult> recognize(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    final text =
        fixedText ??
        'HBL\nFrom: Bright Traders Company\nTo: Azlan Traders\n'
            'Amount: Rs 1,799,200\nTID: TXN123\nYe Rashid ke paise hain';
    return OfflineOcrResult(
      fullText: text,
      lines: [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) OfflineOcrLine(text: line.trim()),
      ],
      engineName: 'Fake Offline OCR',
    );
  }
}
