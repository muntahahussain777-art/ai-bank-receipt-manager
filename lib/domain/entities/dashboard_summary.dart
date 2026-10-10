import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/domain/entities/account_activity.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalReceived,
    required this.totalSent,
    required this.pendingCount,
    required this.enteredCount,
    required this.reconciliationCount,
    required this.accountActivities,
  });

  final double totalReceived;
  final double totalSent;
  final int pendingCount;
  final int enteredCount;
  final int reconciliationCount;
  final List<OfficeAccountActivity> accountActivities;

  static const empty = DashboardSummary(
    totalReceived: 0,
    totalSent: 0,
    pendingCount: 0,
    enteredCount: 0,
    reconciliationCount: 0,
    accountActivities: [],
  );

  /// Convenience for tests that still look up a seeded account by id.
  AccountActivity activityForAccountId(String accountId) {
    for (final item in accountActivities) {
      if (item.account.id == accountId) {
        return AccountActivity(
          received: item.received,
          sent: item.sent,
          count: item.count,
        );
      }
    }
    return AccountActivity.empty;
  }
}
