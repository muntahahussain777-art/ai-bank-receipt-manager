import 'package:ai_bank_receipt_manager/presentation/screens/account_mapping_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/backup_restore_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/calendar_history_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/customers_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/daily_entries_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/dashboard_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/dealers_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/entered_entries_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/ai_processing_settings_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/import_receipts_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/pending_entries_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/receipt_details_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/reconciliation_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/reports_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/settings_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/unknown_route_screen.dart';
import 'package:ai_bank_receipt_manager/presentation/shell/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    errorBuilder: (context, state) {
      return UnknownRouteScreen(location: state.uri.toString());
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/import',
            builder: (context, state) => const ImportReceiptsScreen(),
          ),
          GoRoute(
            path: '/daily',
            builder: (context, state) => const DailyEntriesScreen(),
          ),
          GoRoute(
            path: '/calendar',
            builder: (context, state) => const CalendarHistoryScreen(),
          ),
          GoRoute(
            path: '/pending',
            builder: (context, state) => const PendingEntriesScreen(),
          ),
          GoRoute(
            path: '/entered',
            builder: (context, state) => const EnteredEntriesScreen(),
          ),
          GoRoute(
            path: '/reconciliation',
            builder: (context, state) => const ReconciliationScreen(),
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/dealers',
            builder: (context, state) => const DealersScreen(),
          ),
          GoRoute(
            path: '/mapping',
            builder: (context, state) => const AccountMappingScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  return OfficeAccountDetailsScreen(
                    accountId: state.pathParameters['id'] ?? '',
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/groq',
            builder: (context, state) => const AiProcessingSettingsScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/backup',
            builder: (context, state) => const BackupRestoreScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/receipts/:id',
            builder: (context, state) {
              return ReceiptDetailsScreen(
                receiptId: state.pathParameters['id'] ?? '',
                startInEdit: state.uri.queryParameters['edit'] == 'true',
              );
            },
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
