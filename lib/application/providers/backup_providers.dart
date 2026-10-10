import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/application/security/app_lock_service.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final paths = await ref.watch(appStoragePathsProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  return BackupService(paths: paths, database: db);
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

class AppUnlocked extends Notifier<bool> {
  @override
  bool build() => false;

  void setUnlocked(bool value) => state = value;
}

final appUnlockedProvider = NotifierProvider<AppUnlocked, bool>(
  AppUnlocked.new,
);
