import 'dart:async';

import 'package:ai_bank_receipt_manager/application/import/receipt_ingestion.dart';
import 'package:flutter/services.dart';

/// Receives Android ACTION_SEND / SEND_MULTIPLE image (and PDF) shares.
///
/// Wired via MethodChannel `ai_bank_receipt_manager/share` from MainActivity.
class AndroidShareIngestionSource implements ReceiptIngestionSource {
  AndroidShareIngestionSource({
    MethodChannel? channel,
    EventChannel? eventChannel,
  }) : _channel =
           channel ?? const MethodChannel('ai_bank_receipt_manager/share'),
       _events =
           eventChannel ??
           const EventChannel('ai_bank_receipt_manager/share_events');

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  String get sourceId => 'android_share';

  @override
  String get displayName => 'Android Share Intent (WhatsApp / gallery apps)';

  @override
  Future<bool> get isAvailable async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<IngestedFile>> getInitialFiles() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getInitialShared',
      );
      return _mapFiles(raw);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Stream<List<IngestedFile>> watchIncomingFiles() {
    try {
      return _events.receiveBroadcastStream().map((event) {
        if (event is List) {
          return _mapFiles(event);
        }
        return const <IngestedFile>[];
      });
    } on MissingPluginException {
      return const Stream.empty();
    }
  }

  List<IngestedFile> _mapFiles(List<dynamic>? raw) {
    if (raw == null) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map)
          IngestedFile(
            path: '${item['path'] ?? ''}',
            sourceKind: 'android_share',
            mimeType: item['mimeType'] as String?,
            displayName: item['displayName'] as String?,
            originalUri: item['uri'] as String?,
          ),
    ].where((f) => f.path.isNotEmpty).toList();
  }
}
