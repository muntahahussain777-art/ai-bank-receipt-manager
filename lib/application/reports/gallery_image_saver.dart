import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Saves PNG pages into a Gallery-visible album.
abstract class GalleryImageSaver {
  Future<void> savePng({
    required Uint8List bytes,
    required String fileName,
    required String album,
  });

  Future<bool> hasAccess();

  Future<bool> requestAccess();
}

class GalGalleryImageSaver implements GalleryImageSaver {
  const GalGalleryImageSaver();

  static const albumName = 'AI Bank Receipt Manager';

  @override
  Future<bool> hasAccess() => Gal.hasAccess(toAlbum: true);

  @override
  Future<bool> requestAccess() => Gal.requestAccess(toAlbum: true);

  @override
  Future<void> savePng({
    required Uint8List bytes,
    required String fileName,
    required String album,
  }) {
    return Gal.putImageBytes(bytes, name: fileName, album: album);
  }
}
