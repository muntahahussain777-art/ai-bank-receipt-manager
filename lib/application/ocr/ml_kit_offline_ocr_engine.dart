import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/ocr/offline_ocr_engine.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Google ML Kit Text Recognition (Latin) — free, on-device, MIT-licensed plugin.
///
/// Supports English and Roman Urdu (Latin script). Does not claim full Urdu-script OCR.
class MlKitOfflineOcrEngine implements OfflineOcrEngine {
  MlKitOfflineOcrEngine({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;
  final _uuid = const Uuid();

  @override
  Future<OfflineOcrResult> recognize(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    final dir = await getTemporaryDirectory();
    final ext = (mimeType ?? '').contains('png') ? '.png' : '.jpg';
    final file = File('${dir.path}/ocr_${_uuid.v4()}$ext');
    try {
      await file.writeAsBytes(imageBytes, flush: true);
      final input = InputImage.fromFilePath(file.path);
      final recognized = await _recognizer.processImage(input);
      final lines = <OfflineOcrLine>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim();
          if (text.isEmpty) {
            continue;
          }
          lines.add(OfflineOcrLine(text: text, confidence: line.confidence));
        }
      }
      return OfflineOcrResult(
        fullText: recognized.text.trim(),
        lines: lines,
        engineName: 'ML Kit Text Recognition (Latin)',
      );
    } finally {
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> close() => _recognizer.close();
}
