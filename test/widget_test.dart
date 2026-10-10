import 'package:ai_bank_receipt_manager/app.dart';
import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/backup_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/application/security/app_lock_service.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 1, 1);

final _testAccounts = [
  OfficeAccountRecord(
    id: DefaultOfficeAccountIds.mutalib,
    displayName: 'Mutalib',
    status: OfficeAccountStatus.active,
    createdAt: _now,
    updatedAt: _now,
  ),
  OfficeAccountRecord(
    id: DefaultOfficeAccountIds.ad,
    displayName: 'AD',
    status: OfficeAccountStatus.active,
    createdAt: _now,
    updatedAt: _now,
  ),
];

void main() {
  testWidgets('dashboard shows saved local records empty state', (
    tester,
  ) async {
    await _pumpApp(tester, const Size(1280, 2400));

    expect(find.text('Total Received'), findsOneWidget);
    expect(find.text('Total Sent'), findsOneWidget);
    expect(find.text('Pending Entries'), findsOneWidget);
    expect(find.text('Entered Entries'), findsOneWidget);
    expect(find.text('Reconciliation Required'), findsOneWidget);
    expect(find.text('Office account activity'), findsOneWidget);
    expect(find.text('Mutalib'), findsWidgets);
    expect(find.text('AD'), findsWidgets);
    expect(find.text('Selected accounting date'), findsOneWidget);
    expect(find.textContaining('saved local records'), findsWidgets);
    expect(find.textContaining('Import receipts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard lays out on a narrow screen', (tester) async {
    await _pumpApp(tester, const Size(360, 800));

    expect(find.text('Total Received'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('AD'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('page-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Mutalib'), findsWidgets);
    expect(find.text('AD'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockServiceProvider.overrideWith((ref) => _UnlockedAppLock()),
        officeAccountsProvider.overrideWith((ref) async => _testAccounts),
        selectableOfficeAccountsProvider.overrideWith(
          (ref) async => _testAccounts,
        ),
        storedReceiptsForSelectedDateProvider.overrideWith(
          (ref) async => const <Receipt>[],
        ),
        dailyDeskSummaryProvider.overrideWith(
          (ref) async => DailyDeskSummary(
            accountingDate: DateTime.now(),
            totalCount: 0,
            totalReceived: 0,
            totalSent: 0,
            pendingCount: 0,
            enteredCount: 0,
            reconciliationCount: 0,
            countByAccountId: const {},
            receivedByAccountId: const {},
            sentByAccountId: const {},
          ),
        ),
        storedReceiptCountsByMonthProvider.overrideWith(
          (ref) async => <DateTime, int>{},
        ),
        openReconciliationCasesProvider.overrideWith(
          (ref) async => <ReconciliationCaseRecord>[],
        ),
        openReconciliationSummaryProvider.overrideWith(
          (ref) async => (count: 0, affectedAmount: 0.0),
        ),
      ],
      child: const AiBankReceiptApp(),
    ),
  );
  await tester.pumpAndSettle();
}

class _UnlockedAppLock extends AppLockService {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<bool> biometricEnabled() async => false;
}
