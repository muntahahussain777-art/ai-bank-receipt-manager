import 'dart:io';

import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/database_bootstrap.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiReady = false;

void ensureSqliteFfi() {
  if (_ffiReady) {
    return;
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _ffiReady = true;
}

class TestDbHarness {
  TestDbHarness({
    required this.root,
    required this.paths,
    required this.database,
    required this.receipts,
  });

  final Directory root;
  final AppStoragePaths paths;
  AppDatabase database;
  ReceiptRepository receipts;

  static Future<TestDbHarness> create() async {
    ensureSqliteFfi();
    final root = await Directory.systemTemp.createTemp('ai_bank_db_');
    final paths = await AppStoragePaths.resolve(overrideRoot: root);
    final database = AppDatabase(
      databaseFilePath: paths.databaseFilePath,
      databaseFactory: databaseFactoryFfi,
    );
    final receipts = ReceiptRepository(database);
    await database.database;
    return TestDbHarness(
      root: root,
      paths: paths,
      database: database,
      receipts: receipts,
    );
  }

  Future<AppDatabase> reopen() async {
    await database.close();
    database = AppDatabase(
      databaseFilePath: paths.databaseFilePath,
      databaseFactory: databaseFactoryFfi,
    );
    receipts = ReceiptRepository(database);
    await database.database;
    return database;
  }

  ReceiptImportDraft draft({
    String? transactionId,
    String bankName = 'HBL',
    num amount = 1000,
    String? imageHash,
    DateTime? transactionDateTime,
    String? adminMessage,
    DbReceiptType type = DbReceiptType.received,
  }) {
    return ReceiptImportDraft(
      transactionId: transactionId,
      bankName: bankName,
      amount: amount.toDouble(),
      imageHash: imageHash,
      transactionDateTime: transactionDateTime,
      adminMessage: adminMessage,
      receiptType: type,
    );
  }

  Future<void> dispose() async {
    await database.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }

  String imagePath(String name) => p.join(paths.imagesDirectoryPath, name);
}
