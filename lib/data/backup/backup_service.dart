import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/database_bootstrap.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:path/path.dart' as p;

class BackupManifest {
  const BackupManifest({
    required this.createdAt,
    required this.databaseFileName,
    required this.imageCount,
    required this.appName,
  });

  final DateTime createdAt;
  final String databaseFileName;
  final int imageCount;
  final String appName;

  Map<String, Object?> toJson() => {
    'createdAt': createdAt.toUtc().toIso8601String(),
    'databaseFileName': databaseFileName,
    'imageCount': imageCount,
    'appName': appName,
    'includesApiKeys': false,
  };

  static BackupManifest fromJson(Map<String, Object?> json) {
    return BackupManifest(
      createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      databaseFileName: json['databaseFileName']! as String,
      imageCount: (json['imageCount']! as num).toInt(),
      appName: json['appName']! as String,
    );
  }
}

class BackupResult {
  const BackupResult({required this.archivePath, required this.manifest});

  final String archivePath;
  final BackupManifest manifest;
}

class RestoreResult {
  const RestoreResult({required this.restored, required this.safetyBackupPath});

  final bool restored;
  final String safetyBackupPath;
}

/// Exports and restores the SQLite database with receipt images.
/// API keys in secure storage are never written into the archive.
class BackupService {
  BackupService({required this.paths, required this.database});

  final AppStoragePaths paths;
  final AppDatabase database;

  Future<BackupResult> exportToArchive(String archivePath) async {
    await database.close();
    try {
      final dbFile = File(paths.databaseFilePath);
      if (!dbFile.existsSync()) {
        throw StateError('Database file was not found for backup.');
      }

      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          DbSchema.databaseName,
          dbFile.lengthSync(),
          dbFile.readAsBytesSync(),
        ),
      );

      var imageCount = 0;
      final imagesDir = Directory(paths.imagesDirectoryPath);
      if (imagesDir.existsSync()) {
        for (final entity in imagesDir.listSync(recursive: true)) {
          if (entity is! File) {
            continue;
          }
          final relative = p
              .relative(entity.path, from: paths.imagesDirectoryPath)
              .replaceAll('\\', '/');
          final bytes = entity.readAsBytesSync();
          archive.addFile(
            ArchiveFile('receipt_images/$relative', bytes.length, bytes),
          );
          imageCount += 1;
        }
      }

      final manifest = BackupManifest(
        createdAt: DateTime.now().toUtc(),
        databaseFileName: DbSchema.databaseName,
        imageCount: imageCount,
        appName: 'AI Bank Receipt Manager',
      );
      final manifestBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      final encoded = ZipEncoder().encode(archive);
      final out = File(archivePath);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(Uint8List.fromList(encoded), flush: true);
      return BackupResult(archivePath: archivePath, manifest: manifest);
    } finally {
      // Re-open is lazy via AppDatabase.database.
    }
  }

  /// Restores only after creating a safety backup of the current data.
  /// A failed restore leaves the previous database and images in place.
  Future<RestoreResult> restoreFromArchive({
    required String archivePath,
    required bool confirmReplace,
  }) async {
    if (!confirmReplace) {
      throw StateError('Restore requires explicit confirmation.');
    }

    final archiveFile = File(archivePath);
    if (!archiveFile.existsSync()) {
      throw StateError('Backup archive was not found.');
    }

    await database.close();

    final safetyDir = Directory(
      p.join(
        paths.rootDirectory,
        'safety_backups',
        DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
      ),
    );
    safetyDir.createSync(recursive: true);
    final safetyZip = p.join(safetyDir.path, 'pre_restore_safety.zip');

    // Export current state first (re-open temporarily).
    final safety = await exportToArchive(safetyZip);
    await database.close();

    final decoded = ZipDecoder().decodeBytes(archiveFile.readAsBytesSync());
    final dbEntry = decoded.findFile(DbSchema.databaseName);
    if (dbEntry == null || dbEntry.isFile == false) {
      throw StateError('Backup archive is missing the database file.');
    }

    final staging = Directory(p.join(paths.rootDirectory, 'restore_staging'));
    if (staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
    staging.createSync(recursive: true);

    try {
      final stagedDb = File(p.join(staging.path, DbSchema.databaseName));
      stagedDb.writeAsBytesSync(dbEntry.content, flush: true);

      final stagedImages = Directory(p.join(staging.path, 'receipt_images'));
      stagedImages.createSync(recursive: true);
      for (final file in decoded.files) {
        if (!file.isFile || !file.name.startsWith('receipt_images/')) {
          continue;
        }
        final relative = file.name.substring('receipt_images/'.length);
        if (relative.isEmpty) {
          continue;
        }
        final out = File(p.join(stagedImages.path, relative));
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(file.content, flush: true);
      }

      final liveDb = File(paths.databaseFilePath);
      final liveImages = Directory(paths.imagesDirectoryPath);
      final swapDb = File('${paths.databaseFilePath}.outgoing');
      final swapImages = Directory('${paths.imagesDirectoryPath}.outgoing');

      if (liveDb.existsSync()) {
        liveDb.renameSync(swapDb.path);
      }
      if (liveImages.existsSync()) {
        liveImages.renameSync(swapImages.path);
      }

      try {
        stagedDb.renameSync(paths.databaseFilePath);
        stagedImages.renameSync(paths.imagesDirectoryPath);
        if (swapDb.existsSync()) {
          swapDb.deleteSync();
        }
        if (swapImages.existsSync()) {
          swapImages.deleteSync(recursive: true);
        }
      } catch (_) {
        if (File(paths.databaseFilePath).existsSync()) {
          File(paths.databaseFilePath).deleteSync();
        }
        if (Directory(paths.imagesDirectoryPath).existsSync()) {
          Directory(paths.imagesDirectoryPath).deleteSync(recursive: true);
        }
        if (swapDb.existsSync()) {
          swapDb.renameSync(paths.databaseFilePath);
        }
        if (swapImages.existsSync()) {
          swapImages.renameSync(paths.imagesDirectoryPath);
        }
        rethrow;
      }

      return RestoreResult(
        restored: true,
        safetyBackupPath: safety.archivePath,
      );
    } finally {
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }
  }
}
