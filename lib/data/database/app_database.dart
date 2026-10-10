import 'dart:io';

import 'package:ai_bank_receipt_manager/data/database/database_migrations.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef DatabaseOpener =
    Future<Database> Function({
      required String path,
      required int version,
      Future<void> Function(Database db, int version)? onCreate,
      Future<void> Function(Database db, int oldVersion, int newVersion)?
      onUpgrade,
      Future<void> Function(Database db, int oldVersion, int newVersion)?
      onDowngrade,
    });

/// Opens the local SQLite file. Never deletes or resets the database on open.
class AppDatabase {
  AppDatabase({
    required this.databaseFilePath,
    DatabaseFactory? databaseFactory,
    DatabaseOpener? opener,
  }) : _factory = databaseFactory,
       _opener = opener;

  final String databaseFilePath;
  final DatabaseFactory? _factory;
  final DatabaseOpener? _opener;

  Database? _db;

  String get path => databaseFilePath;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final directory = Directory(p.dirname(databaseFilePath));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    Future<Database> openWithFactory() {
      final factory = _factory ?? databaseFactory;
      return factory.openDatabase(
        databaseFilePath,
        options: OpenDatabaseOptions(
          version: DbSchema.version,
          singleInstance: true,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: DatabaseMigrations.onCreate,
          onUpgrade: DatabaseMigrations.onUpgrade,
          onDowngrade: DatabaseMigrations.onDowngrade,
        ),
      );
    }

    if (_opener != null) {
      return _opener(
        path: databaseFilePath,
        version: DbSchema.version,
        onCreate: DatabaseMigrations.onCreate,
        onUpgrade: DatabaseMigrations.onUpgrade,
        onDowngrade: DatabaseMigrations.onDowngrade,
      );
    }

    return openWithFactory();
  }

  Future<void> close() async {
    final existing = _db;
    _db = null;
    if (existing != null && existing.isOpen) {
      await existing.close();
    }
  }
}
