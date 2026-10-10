import 'dart:io';

import 'package:ai_bank_receipt_manager/application/ai/ai_settings_service.dart';
import 'package:ai_bank_receipt_manager/application/ai/api_connection_tester.dart';
import 'package:ai_bank_receipt_manager/application/ai/receipt_processing_coordinator.dart';
import 'package:ai_bank_receipt_manager/application/groq/groq_key_manager.dart';
import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/import/android_share_ingestion.dart';
import 'package:ai_bank_receipt_manager/application/import/batch_import_service.dart';
import 'package:ai_bank_receipt_manager/application/import/receipt_ingestion.dart';
import 'package:ai_bank_receipt_manager/application/ocr/ml_kit_offline_ocr_engine.dart';
import 'package:ai_bank_receipt_manager/application/ocr/offline_ocr_engine.dart';
import 'package:ai_bank_receipt_manager/data/database/app_database.dart';
import 'package:ai_bank_receipt_manager/data/database/database_bootstrap.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/import_queue_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

final appStoragePathsProvider = FutureProvider<AppStoragePaths>((ref) {
  return AppStoragePaths.resolve();
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final paths = await ref.watch(appStoragePathsProvider.future);
  final database = AppDatabase(
    databaseFilePath: paths.databaseFilePath,
    databaseFactory: databaseFactory,
  );
  await database.database;
  ref.onDispose(database.close);
  return database;
});

final officeAccountRepositoryProvider = FutureProvider<OfficeAccountRepository>(
  (ref) async {
    final db = await ref.watch(appDatabaseProvider.future);
    return OfficeAccountRepository(db);
  },
);

final customerRepositoryProvider = FutureProvider<CustomerRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return CustomerRepository(db);
});

final dealerRepositoryProvider = FutureProvider<DealerRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DealerRepository(db);
});

final receiptRepositoryProvider = FutureProvider<ReceiptRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ReceiptRepository(db);
});

final appSettingsRepositoryProvider = FutureProvider<AppSettingsRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return AppSettingsRepository(db);
});

final groqApiConfigurationRepositoryProvider =
    FutureProvider<GroqApiConfigurationRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      return GroqApiConfigurationRepository(db);
    });

final aiExtractionRepositoryProvider = FutureProvider<AiExtractionRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return AiExtractionRepository(db);
});

final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return FlutterSecureKeyStore();
});

final groqKeyManagerProvider = FutureProvider<GroqKeyManager>((ref) async {
  final configs = await ref.watch(
    groqApiConfigurationRepositoryProvider.future,
  );
  return GroqKeyManager(
    configs: configs,
    keyStore: ref.watch(secureKeyStoreProvider),
  );
});

final receiptVisionServiceProvider = FutureProvider<ReceiptVisionService>((
  ref,
) async {
  final paths = await ref.watch(appStoragePathsProvider.future);
  final keyManager = await ref.watch(groqKeyManagerProvider.future);
  final configs = await ref.watch(
    groqApiConfigurationRepositoryProvider.future,
  );
  final extractions = await ref.watch(aiExtractionRepositoryProvider.future);
  final receipts = await ref.watch(receiptRepositoryProvider.future);
  return ReceiptVisionService(
    keyManager: keyManager,
    configs: configs,
    extractions: extractions,
    receipts: receipts,
    imagesDirectoryPath: paths.imagesDirectoryPath,
  );
});

final aiSettingsServiceProvider = FutureProvider<AiSettingsService>((
  ref,
) async {
  final settings = await ref.watch(appSettingsRepositoryProvider.future);
  return AiSettingsService(settings);
});

final offlineOcrEngineProvider = Provider<OfflineOcrEngine>((ref) {
  if (Platform.isAndroid) {
    return MlKitOfflineOcrEngine();
  }
  return FakeOfflineOcrEngine();
});

final apiConnectionTesterProvider = FutureProvider<ApiConnectionTester>((
  ref,
) async {
  final configs = await ref.watch(
    groqApiConfigurationRepositoryProvider.future,
  );
  return ApiConnectionTester(
    configs: configs,
    keyStore: ref.watch(secureKeyStoreProvider),
  );
});

final receiptProcessingCoordinatorProvider =
    FutureProvider<ReceiptProcessingCoordinator>((ref) async {
      final paths = await ref.watch(appStoragePathsProvider.future);
      final settings = await ref.watch(aiSettingsServiceProvider.future);
      final configs = await ref.watch(
        groqApiConfigurationRepositoryProvider.future,
      );
      final extractions = await ref.watch(
        aiExtractionRepositoryProvider.future,
      );
      final vision = await ref.watch(receiptVisionServiceProvider.future);
      return ReceiptProcessingCoordinator(
        settings: settings,
        configs: configs,
        keyStore: ref.watch(secureKeyStoreProvider),
        extractions: extractions,
        imagesDirectoryPath: paths.imagesDirectoryPath,
        ocrEngine: ref.watch(offlineOcrEngineProvider),
        groqVision: vision,
      );
    });

final importQueueRepositoryProvider = FutureProvider<ImportQueueRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ImportQueueRepository(db);
});

final batchImportServiceProvider = FutureProvider<BatchImportService>((
  ref,
) async {
  final paths = await ref.watch(appStoragePathsProvider.future);
  final queue = await ref.watch(importQueueRepositoryProvider.future);
  final receipts = await ref.watch(receiptRepositoryProvider.future);
  final vision = await ref.watch(receiptVisionServiceProvider.future);
  final coordinator = await ref.watch(
    receiptProcessingCoordinatorProvider.future,
  );
  return BatchImportService(
    queue: queue,
    receipts: receipts,
    vision: vision,
    coordinator: coordinator,
    imagesDirectoryPath: paths.imagesDirectoryPath,
  );
});

/// Primary share ingestion. Swap/add sources without changing the batch pipeline.
final androidShareIngestionProvider = Provider<ReceiptIngestionSource>((ref) {
  return AndroidShareIngestionSource();
});

final recentImportBatchesProvider = FutureProvider.autoDispose((ref) async {
  final queue = await ref.watch(importQueueRepositoryProvider.future);
  return queue.listRecentBatches();
});
