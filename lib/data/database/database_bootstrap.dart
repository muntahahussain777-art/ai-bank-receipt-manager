import 'dart:io';

import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppStoragePaths {
  const AppStoragePaths({
    required this.rootDirectory,
    required this.databaseFilePath,
    required this.imagesDirectoryPath,
  });

  final String rootDirectory;
  final String databaseFilePath;
  final String imagesDirectoryPath;

  Directory get imagesDirectory => Directory(imagesDirectoryPath);

  static Future<AppStoragePaths> resolve({Directory? overrideRoot}) async {
    late final Directory root;
    if (overrideRoot != null) {
      root = overrideRoot;
    } else {
      final documents = await getApplicationDocumentsDirectory();
      root = Directory(p.join(documents.path, 'ai_bank_receipt_manager'));
    }
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    final images = Directory(p.join(root.path, 'receipt_images'));
    if (!images.existsSync()) {
      images.createSync(recursive: true);
    }
    return AppStoragePaths(
      rootDirectory: root.path,
      databaseFilePath: p.join(root.path, DbSchema.databaseName),
      imagesDirectoryPath: images.path,
    );
  }
}

class DatabaseBootstrap {
  DatabaseBootstrap({required this.paths, DatabaseFactory? databaseFactory})
    : _factory = databaseFactory;

  final AppStoragePaths paths;
  final DatabaseFactory? _factory;

  AppDatabase createDatabase() {
    return AppDatabase(
      databaseFilePath: paths.databaseFilePath,
      databaseFactory: _factory,
    );
  }
}
