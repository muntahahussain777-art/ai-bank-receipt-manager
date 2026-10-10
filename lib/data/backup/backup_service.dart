import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_crypto.dart';
import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/database_bootstrap.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BackupManifest {
  const BackupManifest({
    required this.createdAt,
    required this.databaseFileName,
    required this.imageCount,
    required this.appName,
    required this.schemaVersion,
    required this.archiveFormatVersion,
    required this.contentSha256,
    required this.receiptCount,
    required this.customerCount,
    required this.dealerCount,
    required this.officeAccountCount,
    required this.auditCount,
    required this.reconciliationCaseCount,
    required this.importBatchCount,
    required this.enteredCount,
    required this.pendingCount,
    this.fileSizeBytes,
    this.encrypted = false,
    this.includesApiKeys = false,
  });

  final DateTime createdAt;
  final String databaseFileName;
  final int imageCount;
  final String appName;
  final int schemaVersion;
  final int archiveFormatVersion;
  final String contentSha256;
  final int receiptCount;
  final int customerCount;
  final int dealerCount;
  final int officeAccountCount;
  final int auditCount;
  final int reconciliationCaseCount;
  final int importBatchCount;
  final int enteredCount;
  final int pendingCount;
  final int? fileSizeBytes;
  final bool encrypted;
  final bool includesApiKeys;

  static const currentArchiveFormatVersion = 2;

  Map<String, Object?> toJson() => {
    'createdAt': createdAt.toUtc().toIso8601String(),
    'databaseFileName': databaseFileName,
    'imageCount': imageCount,
    'appName': appName,
    'schemaVersion': schemaVersion,
    'archiveFormatVersion': archiveFormatVersion,
    'contentSha256': contentSha256,
    'receiptCount': receiptCount,
    'customerCount': customerCount,
    'dealerCount': dealerCount,
    'officeAccountCount': officeAccountCount,
    'auditCount': auditCount,
    'reconciliationCaseCount': reconciliationCaseCount,
    'importBatchCount': importBatchCount,
    'enteredCount': enteredCount,
    'pendingCount': pendingCount,
    'fileSizeBytes': fileSizeBytes,
    'encrypted': encrypted,
    'includesApiKeys': includesApiKeys,
  };

  static BackupManifest fromJson(Map<String, Object?> json) {
    return BackupManifest(
      createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      databaseFileName: json['databaseFileName']! as String,
      imageCount: (json['imageCount'] as num?)?.toInt() ?? 0,
      appName: json['appName'] as String? ?? 'AI Bank Receipt Manager',
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      archiveFormatVersion:
          (json['archiveFormatVersion'] as num?)?.toInt() ?? 1,
      contentSha256: json['contentSha256'] as String? ?? '',
      receiptCount: (json['receiptCount'] as num?)?.toInt() ?? 0,
      customerCount: (json['customerCount'] as num?)?.toInt() ?? 0,
      dealerCount: (json['dealerCount'] as num?)?.toInt() ?? 0,
      officeAccountCount: (json['officeAccountCount'] as num?)?.toInt() ?? 0,
      auditCount: (json['auditCount'] as num?)?.toInt() ?? 0,
      reconciliationCaseCount:
          (json['reconciliationCaseCount'] as num?)?.toInt() ?? 0,
      importBatchCount: (json['importBatchCount'] as num?)?.toInt() ?? 0,
      enteredCount: (json['enteredCount'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
      encrypted: json['encrypted'] == true,
      includesApiKeys: json['includesApiKeys'] == true,
    );
  }

  BackupManifest copyWith({int? fileSizeBytes, bool? encrypted}) {
    return BackupManifest(
      createdAt: createdAt,
      databaseFileName: databaseFileName,
      imageCount: imageCount,
      appName: appName,
      schemaVersion: schemaVersion,
      archiveFormatVersion: archiveFormatVersion,
      contentSha256: contentSha256,
      receiptCount: receiptCount,
      customerCount: customerCount,
      dealerCount: dealerCount,
      officeAccountCount: officeAccountCount,
      auditCount: auditCount,
      reconciliationCaseCount: reconciliationCaseCount,
      importBatchCount: importBatchCount,
      enteredCount: enteredCount,
      pendingCount: pendingCount,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      encrypted: encrypted ?? this.encrypted,
      includesApiKeys: includesApiKeys,
    );
  }
}

class BackupPreview {
  const BackupPreview({
    required this.manifest,
    required this.archivePath,
    required this.isEncrypted,
    required this.integrityOk,
    this.integrityError,
  });

  final BackupManifest manifest;
  final String archivePath;
  final bool isEncrypted;
  final bool integrityOk;
  final String? integrityError;
}

class BackupResult {
  const BackupResult({
    required this.archivePath,
    required this.manifest,
    required this.verified,
  });

  final String archivePath;
  final BackupManifest manifest;
  final bool verified;
}

class RestoreResult {
  const RestoreResult({
    required this.restored,
    required this.safetyBackupPath,
    required this.verifiedCounts,
    this.missingImageCount = 0,
  });

  final bool restored;
  final String safetyBackupPath;
  final bool verifiedCounts;
  final int missingImageCount;
}

class BackupCountSnapshot {
  const BackupCountSnapshot({
    required this.receiptCount,
    required this.customerCount,
    required this.dealerCount,
    required this.officeAccountCount,
    required this.auditCount,
    required this.reconciliationCaseCount,
    required this.importBatchCount,
    required this.enteredCount,
    required this.pendingCount,
  });

  final int receiptCount;
  final int customerCount;
  final int dealerCount;
  final int officeAccountCount;
  final int auditCount;
  final int reconciliationCaseCount;
  final int importBatchCount;
  final int enteredCount;
  final int pendingCount;
}

/// Exports and restores the SQLite database with receipt images.
/// API keys in secure storage are never written into the archive.
class BackupService {
  BackupService({
    required this.paths,
    required this.database,
    BackupCrypto? crypto,
  }) : _crypto = crypto ?? BackupCrypto();

  final AppStoragePaths paths;
  final AppDatabase database;
  final BackupCrypto _crypto;

  Directory get versionedBackupDirectory {
    final dir = Directory(p.join(paths.rootDirectory, 'backups'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Manual full backup to a versioned archive path under [versionedBackupDirectory]
  /// unless [archivePath] is provided (e.g. user-chosen external location).
  Future<BackupResult> createFullBackup({
    String? archivePath,
    String? password,
  }) async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final encrypted = password != null && password.trim().isNotEmpty;
    final ext = encrypted ? 'aibackup' : 'zip';
    final target =
        archivePath ??
        p.join(versionedBackupDirectory.path, 'backup_$stamp.$ext');
    return exportToArchive(target, password: password);
  }

  Future<BackupResult> exportToArchive(
    String archivePath, {
    String? password,
  }) async {
    await database.close();
    try {
      final built = await _buildZipBytes();
      var bytesToWrite = built.zipBytes;
      var manifest = built.manifest;

      if (password != null && password.trim().isNotEmpty) {
        bytesToWrite = await _crypto.encryptZip(
          zipBytes: built.zipBytes,
          password: password,
          manifestPreview: manifest.copyWith(encrypted: true).toJson(),
        );
        manifest = manifest.copyWith(encrypted: true);
      }

      final out = File(archivePath);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(bytesToWrite, flush: true);

      // Never claim success before verifying the created archive.
      final preview = await inspectArchive(archivePath, password: password);
      if (!preview.integrityOk) {
        out.deleteSync();
        throw StateError(
          'Backup verification failed: ${preview.integrityError}',
        );
      }

      final sized = preview.manifest.copyWith(
        fileSizeBytes: out.lengthSync(),
        encrypted: password != null && password.trim().isNotEmpty,
      );
      return BackupResult(
        archivePath: archivePath,
        manifest: sized,
        verified: true,
      );
    } finally {
      // Re-open is lazy via AppDatabase.database.
    }
  }

  Future<BackupPreview> inspectArchive(
    String archivePath, {
    String? password,
  }) async {
    final file = File(archivePath);
    if (!file.existsSync()) {
      throw StateError('Backup archive was not found.');
    }
    final raw = file.readAsBytesSync();
    final encrypted = BackupCrypto.looksEncrypted(raw);
    late final Uint8List zipBytes;
    try {
      if (encrypted) {
        if (password == null || password.trim().isEmpty) {
          final previewMap = _tryReadEncryptedPreview(raw);
          final manifest = previewMap == null
              ? BackupManifest(
                  createdAt: DateTime.now().toUtc(),
                  databaseFileName: DbSchema.databaseName,
                  imageCount: 0,
                  appName: 'AI Bank Receipt Manager',
                  schemaVersion: DbSchema.version,
                  archiveFormatVersion:
                      BackupManifest.currentArchiveFormatVersion,
                  contentSha256: '',
                  receiptCount: 0,
                  customerCount: 0,
                  dealerCount: 0,
                  officeAccountCount: 0,
                  auditCount: 0,
                  reconciliationCaseCount: 0,
                  importBatchCount: 0,
                  enteredCount: 0,
                  pendingCount: 0,
                  encrypted: true,
                  fileSizeBytes: raw.length,
                )
              : BackupManifest.fromJson(
                  previewMap,
                ).copyWith(encrypted: true, fileSizeBytes: raw.length);
          return BackupPreview(
            manifest: manifest,
            archivePath: archivePath,
            isEncrypted: true,
            integrityOk: false,
            integrityError: 'Password required for encrypted backup.',
          );
        }
        zipBytes = await _crypto.decryptToZip(
          envelopeBytes: Uint8List.fromList(raw),
          password: password,
        );
      } else {
        zipBytes = Uint8List.fromList(raw);
      }
    } catch (error) {
      return BackupPreview(
        manifest: BackupManifest(
          createdAt: DateTime.now().toUtc(),
          databaseFileName: DbSchema.databaseName,
          imageCount: 0,
          appName: 'AI Bank Receipt Manager',
          schemaVersion: DbSchema.version,
          archiveFormatVersion: BackupManifest.currentArchiveFormatVersion,
          contentSha256: '',
          receiptCount: 0,
          customerCount: 0,
          dealerCount: 0,
          officeAccountCount: 0,
          auditCount: 0,
          reconciliationCaseCount: 0,
          importBatchCount: 0,
          enteredCount: 0,
          pendingCount: 0,
          encrypted: encrypted,
          fileSizeBytes: raw.length,
        ),
        archivePath: archivePath,
        isEncrypted: encrypted,
        integrityOk: false,
        integrityError: '$error',
      );
    }

    try {
      final decoded = ZipDecoder().decodeBytes(zipBytes);
      final manifestEntry = decoded.findFile('manifest.json');
      if (manifestEntry == null || !manifestEntry.isFile) {
        throw StateError('Backup is missing manifest.json.');
      }
      final manifestJson = jsonDecode(
        utf8.decode(manifestEntry.content as List<int>),
      );
      if (manifestJson is! Map) {
        throw StateError('Backup manifest is invalid.');
      }
      final manifest = BackupManifest.fromJson(
        Map<String, Object?>.from(manifestJson),
      ).copyWith(fileSizeBytes: raw.length, encrypted: encrypted);

      final dbEntry = decoded.findFile(manifest.databaseFileName);
      if (dbEntry == null || !dbEntry.isFile) {
        throw StateError('Backup archive is missing the database file.');
      }

      final recomputed = _contentHashFromArchive(decoded);
      if (manifest.contentSha256.isNotEmpty &&
          recomputed != manifest.contentSha256) {
        throw StateError('Archive integrity hash mismatch.');
      }

      return BackupPreview(
        manifest: manifest,
        archivePath: archivePath,
        isEncrypted: encrypted,
        integrityOk: true,
      );
    } catch (error) {
      return BackupPreview(
        manifest: BackupManifest(
          createdAt: DateTime.now().toUtc(),
          databaseFileName: DbSchema.databaseName,
          imageCount: 0,
          appName: 'AI Bank Receipt Manager',
          schemaVersion: DbSchema.version,
          archiveFormatVersion: BackupManifest.currentArchiveFormatVersion,
          contentSha256: '',
          receiptCount: 0,
          customerCount: 0,
          dealerCount: 0,
          officeAccountCount: 0,
          auditCount: 0,
          reconciliationCaseCount: 0,
          importBatchCount: 0,
          enteredCount: 0,
          pendingCount: 0,
          encrypted: encrypted,
          fileSizeBytes: raw.length,
        ),
        archivePath: archivePath,
        isEncrypted: encrypted,
        integrityOk: false,
        integrityError: '$error',
      );
    }
  }

  /// Restores only after creating a safety backup of the current data.
  /// A failed restore leaves the previous database and images in place.
  Future<RestoreResult> restoreFromArchive({
    required String archivePath,
    required bool confirmReplace,
    String? password,
  }) async {
    if (!confirmReplace) {
      throw StateError('Restore requires explicit confirmation.');
    }

    final preview = await inspectArchive(archivePath, password: password);
    if (!preview.integrityOk) {
      throw StateError(
        'Cannot restore: ${preview.integrityError ?? 'integrity check failed'}',
      );
    }
    if (preview.manifest.schemaVersion > DbSchema.version) {
      throw StateError(
        'Backup schema v${preview.manifest.schemaVersion} is newer than '
        'this app (v${DbSchema.version}). Upgrade the app before restore.',
      );
    }
    if (preview.manifest.includesApiKeys) {
      throw StateError('Refusing backup that claims to include API keys.');
    }

    final archiveFile = File(archivePath);
    final raw = archiveFile.readAsBytesSync();
    final zipBytes = BackupCrypto.looksEncrypted(raw)
        ? await _crypto.decryptToZip(
            envelopeBytes: Uint8List.fromList(raw),
            password: password ?? '',
          )
        : Uint8List.fromList(raw);

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

    final safety = await exportToArchive(safetyZip);
    await database.close();

    final decoded = ZipDecoder().decodeBytes(zipBytes);
    final dbEntry = decoded.findFile(preview.manifest.databaseFileName);
    if (dbEntry == null || dbEntry.isFile == false) {
      throw StateError('Backup archive is missing the database file.');
    }

    final staging = Directory(p.join(paths.rootDirectory, 'restore_staging'));
    if (staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
    staging.createSync(recursive: true);

    var missingImages = 0;
    try {
      final stagedDb = File(p.join(staging.path, DbSchema.databaseName));
      stagedDb.writeAsBytesSync(
        List<int>.from(dbEntry.content as List<int>),
        flush: true,
      );

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
        try {
          final out = File(p.join(stagedImages.path, relative));
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(
            List<int>.from(file.content as List<int>),
            flush: true,
          );
        } catch (_) {
          missingImages += 1;
        }
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
        if (stagedImages.existsSync()) {
          stagedImages.renameSync(paths.imagesDirectoryPath);
        } else {
          Directory(paths.imagesDirectoryPath).createSync(recursive: true);
        }
        if (swapDb.existsSync()) {
          swapDb.deleteSync();
        }
        if (swapImages.existsSync()) {
          swapImages.deleteSync(recursive: true);
        }
      } catch (_) {
        // Interrupted / failed swap — put previous data back.
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

      // Verify restored counts before claiming success.
      final verified = await _verifyRestoredCounts(preview.manifest);
      if (!verified) {
        await _installZipFile(safety.archivePath);
        throw StateError(
          'Restore verification failed; previous data was reinstated '
          'from the safety backup.',
        );
      }

      missingImages += await _countMissingReferencedImages();

      return RestoreResult(
        restored: true,
        safetyBackupPath: safety.archivePath,
        verifiedCounts: true,
        missingImageCount: missingImages,
      );
    } finally {
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }
  }

  /// Installs a plain zip backup over live paths without nested safety backup.
  Future<void> _installZipFile(String zipPath) async {
    final bytes = File(zipPath).readAsBytesSync();
    final decoded = ZipDecoder().decodeBytes(bytes);
    final dbEntry = decoded.findFile(DbSchema.databaseName);
    if (dbEntry == null || !dbEntry.isFile) {
      throw StateError('Safety backup is missing the database file.');
    }
    final staging = Directory(
      p.join(paths.rootDirectory, 'restore_rollback_staging'),
    );
    if (staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
    staging.createSync(recursive: true);
    try {
      final stagedDb = File(p.join(staging.path, DbSchema.databaseName));
      stagedDb.writeAsBytesSync(
        List<int>.from(dbEntry.content as List<int>),
        flush: true,
      );
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
        out.writeAsBytesSync(
          List<int>.from(file.content as List<int>),
          flush: true,
        );
      }
      final liveDb = File(paths.databaseFilePath);
      final liveImages = Directory(paths.imagesDirectoryPath);
      if (liveDb.existsSync()) {
        liveDb.deleteSync();
      }
      if (liveImages.existsSync()) {
        liveImages.deleteSync(recursive: true);
      }
      stagedDb.renameSync(paths.databaseFilePath);
      stagedImages.renameSync(paths.imagesDirectoryPath);
    } finally {
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }
  }

  Future<List<File>> listVersionedBackups() async {
    final dir = versionedBackupDirectory;
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) => f.path.endsWith('.zip') || f.path.endsWith('.aibackup'),
            )
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<({Uint8List zipBytes, BackupManifest manifest})>
  _buildZipBytes() async {
    final dbFile = File(paths.databaseFilePath);
    if (!dbFile.existsSync()) {
      throw StateError('Database file was not found for backup.');
    }

    // Open read-only snapshot counts from a temporary connection.
    final counts = await _readCountsFromFile(dbFile.path);
    final archive = Archive();
    final dbBytes = dbFile.readAsBytesSync();
    archive.addFile(
      ArchiveFile(DbSchema.databaseName, dbBytes.length, dbBytes),
    );

    var imageCount = 0;
    final hashParts = <String>[sha256Hex(dbBytes)];
    final imagesDir = Directory(paths.imagesDirectoryPath);
    if (imagesDir.existsSync()) {
      final files =
          imagesDir.listSync(recursive: true).whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final entity in files) {
        final relative = p
            .relative(entity.path, from: paths.imagesDirectoryPath)
            .replaceAll('\\', '/');
        final bytes = entity.readAsBytesSync();
        archive.addFile(
          ArchiveFile('receipt_images/$relative', bytes.length, bytes),
        );
        hashParts.add('$relative:${sha256Hex(bytes)}');
        imageCount += 1;
      }
    }

    final contentSha256 = sha256HexOfString(hashParts.join('|'));
    final manifest = BackupManifest(
      createdAt: DateTime.now().toUtc(),
      databaseFileName: DbSchema.databaseName,
      imageCount: imageCount,
      appName: 'AI Bank Receipt Manager',
      schemaVersion: DbSchema.version,
      archiveFormatVersion: BackupManifest.currentArchiveFormatVersion,
      contentSha256: contentSha256,
      receiptCount: counts.receiptCount,
      customerCount: counts.customerCount,
      dealerCount: counts.dealerCount,
      officeAccountCount: counts.officeAccountCount,
      auditCount: counts.auditCount,
      reconciliationCaseCount: counts.reconciliationCaseCount,
      importBatchCount: counts.importBatchCount,
      enteredCount: counts.enteredCount,
      pendingCount: counts.pendingCount,
      includesApiKeys: false,
      encrypted: false,
    );
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('Failed to encode backup archive.');
    }
    return (zipBytes: Uint8List.fromList(encoded), manifest: manifest);
  }

  String _contentHashFromArchive(Archive decoded) {
    final hashParts = <String>[];
    final db = decoded.findFile(DbSchema.databaseName);
    if (db != null && db.isFile) {
      hashParts.add(sha256Hex(db.content as List<int>));
    }
    final imageFiles =
        decoded.files
            .where((f) => f.isFile && f.name.startsWith('receipt_images/'))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    for (final file in imageFiles) {
      final relative = file.name.substring('receipt_images/'.length);
      hashParts.add('$relative:${sha256Hex(file.content as List<int>)}');
    }
    return sha256HexOfString(hashParts.join('|'));
  }

  Future<BackupCountSnapshot> _readCountsFromFile(String dbPath) async {
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      Future<int> count(String sql, [List<Object?> args = const []]) async {
        final rows = await db.rawQuery(sql, args);
        return (rows.first.values.first as num).toInt();
      }

      return BackupCountSnapshot(
        receiptCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.receipts} WHERE deleted_at IS NULL',
        ),
        customerCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.customers} WHERE deleted_at IS NULL',
        ),
        dealerCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.dealers} WHERE deleted_at IS NULL',
        ),
        officeAccountCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.accountMappings} WHERE deleted_at IS NULL',
        ),
        auditCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.receiptAudit}',
        ),
        reconciliationCaseCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.reconciliationCases}',
        ),
        importBatchCount: await count(
          'SELECT COUNT(*) FROM ${DbSchema.importBatches}',
        ),
        enteredCount: await count(
          "SELECT COUNT(*) FROM ${DbSchema.receipts} "
          "WHERE deleted_at IS NULL AND entry_status = 'entered'",
        ),
        pendingCount: await count(
          "SELECT COUNT(*) FROM ${DbSchema.receipts} "
          "WHERE deleted_at IS NULL AND entry_status = 'pending'",
        ),
      );
    } finally {
      await db.close();
    }
  }

  Future<bool> _verifyRestoredCounts(BackupManifest manifest) async {
    final live = await _readCountsFromFile(paths.databaseFilePath);
    return live.receiptCount == manifest.receiptCount &&
        live.enteredCount == manifest.enteredCount &&
        live.pendingCount == manifest.pendingCount &&
        live.customerCount == manifest.customerCount &&
        live.dealerCount == manifest.dealerCount &&
        live.officeAccountCount == manifest.officeAccountCount &&
        live.reconciliationCaseCount == manifest.reconciliationCaseCount;
  }

  /// Counts receipt image paths that are missing after restore (non-fatal).
  Future<int> _countMissingReferencedImages() async {
    final db = await openDatabase(
      paths.databaseFilePath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final rows = await db.rawQuery(
        'SELECT original_image_path FROM ${DbSchema.receipts} '
        'WHERE deleted_at IS NULL AND original_image_path IS NOT NULL',
      );
      var missing = 0;
      for (final row in rows) {
        final path = row['original_image_path'] as String?;
        if (path == null || path.isEmpty) {
          continue;
        }
        if (!File(path).existsSync()) {
          // Also accept images restored under the live images directory by basename.
          final byName = File(
            p.join(paths.imagesDirectoryPath, p.basename(path)),
          );
          if (!byName.existsSync()) {
            missing += 1;
          }
        }
      }
      return missing;
    } finally {
      await db.close();
    }
  }

  Map<String, Object?>? _tryReadEncryptedPreview(List<int> raw) {
    try {
      final map = jsonDecode(utf8.decode(raw));
      if (map is! Map) {
        return null;
      }
      final preview = map['manifestPreview'];
      if (preview is Map) {
        return Map<String, Object?>.from(preview);
      }
    } catch (_) {}
    return null;
  }
}
