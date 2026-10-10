import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/domain/entities/reconciliation_preview.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/reconciliation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const preview = ReconciliationPreview(
    reference: 'JC-778210',
    oldAmount: 40000,
    newAmount: 45000,
    oldParty: 'Bilal Ahmed',
    newParty: 'Bilal Ahmed',
    oldOfficeAccount: OfficeAccount.mutalib,
    newOfficeAccount: OfficeAccount.mutalib,
  );

  testWidgets('reconciliation dialog shows old and new values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showReconciliationDialog(context, preview: preview);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Old financial values'), findsOneWidget);
    expect(find.text('New financial values'), findsOneWidget);
    expect(find.text('WinForms correction'), findsOneWidget);
    expect(find.text(formatPkr(40000)), findsOneWidget);
    expect(find.text(formatPkr(45000)), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('WinForms'), findsWidgets);

    await tester.tap(find.byKey(const Key('reconciliation-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Reconciliation required'), findsNothing);
  });

  testWidgets('confirm closes the dialog without a success message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _ConfirmHarness())),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reconciliation-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Reconciliation required'), findsNothing);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Reviewed only'), findsOneWidget);
  });
}

class _ConfirmHarness extends StatefulWidget {
  const _ConfirmHarness();

  @override
  State<_ConfirmHarness> createState() => _ConfirmHarnessState();
}

class _ConfirmHarnessState extends State<_ConfirmHarness> {
  var _reviewed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () async {
            final confirmed = await showReconciliationDialog(
              context,
              preview: const ReconciliationPreview(
                reference: 'JC-778210',
                oldAmount: 40000,
                newAmount: 45000,
                oldParty: 'Bilal Ahmed',
                newParty: 'Bilal Ahmed',
                oldOfficeAccount: OfficeAccount.mutalib,
                newOfficeAccount: OfficeAccount.mutalib,
              ),
            );
            if (!mounted || !confirmed) {
              return;
            }
            setState(() => _reviewed = true);
          },
          child: const Text('Open'),
        ),
        if (_reviewed) const Text('Reviewed only'),
      ],
    );
  }
}
