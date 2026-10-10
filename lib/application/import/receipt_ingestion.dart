import 'dart:async';

/// Documented extension point for future authorized automatic ingestion.
///
/// Ordinary personal WhatsApp groups cannot be read through an official
/// unrestricted API. This app implements reliable Android Share Intent and
/// manual import first. A later official/supported integration can plug in
/// here without changing the receipt processing pipeline.
///
/// Do not implement unofficial WhatsApp scraping or accessibility automation.
abstract class ReceiptIngestionSource {
  /// Stable id for diagnostics (e.g. `android_share`, `gallery`, `camera`).
  String get sourceId;

  /// Human-readable label for settings / docs.
  String get displayName;

  /// Whether this source is currently available on the platform.
  Future<bool> get isAvailable;

  /// Cold-start payload (e.g. share that launched the app).
  Future<List<IngestedFile>> getInitialFiles();

  /// Live shares while the app is open.
  Stream<List<IngestedFile>> watchIncomingFiles();
}

class IngestedFile {
  const IngestedFile({
    required this.path,
    required this.sourceKind,
    this.mimeType,
    this.displayName,
    this.originalUri,
  });

  final String path;
  final String sourceKind;
  final String? mimeType;
  final String? displayName;
  final String? originalUri;

  bool get isPdf =>
      (mimeType?.toLowerCase().contains('pdf') ?? false) ||
      path.toLowerCase().endsWith('.pdf');

  bool get isImage {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) {
      return true;
    }
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }
}

/// No-op source used in tests and when a channel is unavailable.
class EmptyIngestionSource implements ReceiptIngestionSource {
  @override
  String get sourceId => 'empty';

  @override
  String get displayName => 'None';

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<List<IngestedFile>> getInitialFiles() async => const [];

  @override
  Stream<List<IngestedFile>> watchIncomingFiles() => const Stream.empty();
}

/// Test/double that pushes shared files into the same pipeline as WhatsApp share.
class ControllableIngestionSource implements ReceiptIngestionSource {
  ControllableIngestionSource({
    this.sourceId = 'test_share',
    this.displayName = 'Test share',
  });

  @override
  final String sourceId;

  @override
  final String displayName;

  final _controller = StreamController<List<IngestedFile>>.broadcast();
  List<IngestedFile> _initial = const [];

  void setInitial(List<IngestedFile> files) => _initial = files;

  void emit(List<IngestedFile> files) => _controller.add(files);

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<IngestedFile>> getInitialFiles() async => _initial;

  @override
  Stream<List<IngestedFile>> watchIncomingFiles() => _controller.stream;

  Future<void> dispose() => _controller.close();
}
