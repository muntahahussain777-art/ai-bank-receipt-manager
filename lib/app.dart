import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/core/theme/app_theme.dart';
import 'package:ai_bank_receipt_manager/presentation/router/app_router.dart';
import 'package:ai_bank_receipt_manager/presentation/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiBankReceiptApp extends ConsumerWidget {
  const AiBankReceiptApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLockGate(
      child: MaterialApp.router(
        title: 'AI Bank Receipt Manager',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: ref.watch(routerProvider),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
