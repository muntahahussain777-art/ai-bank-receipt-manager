import 'package:ai_bank_receipt_manager/application/dashboard/summarize_receipts.dart';
import 'package:ai_bank_receipt_manager/application/reconciliation/build_reconciliation_preview.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/preview/preview_data.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default seed names remain available as editable defaults', () {
    expect(BusinessRules.defaultMutalibDisplayName, 'Mutalib');
    expect(BusinessRules.defaultMutalibBankAlias, 'Azlan Traders');
    expect(BusinessRules.defaultAdDisplayName, 'AD');
    expect(BusinessRules.defaultAdBankAlias, 'Habib Enterprise');
    expect(OfficeAccount.mutalib.legalName, 'Azlan Traders');
  });

  test(
    'selected-date summary separates received and sent for dynamic accounts',
    () {
      final octoberTen = previewReceipts
          .where((receipt) => receipt.accountingDate == DateTime(2026, 10, 10))
          .toList();
      final summary = summarizeReceiptsForAccounts(
        receipts: octoberTen,
        accounts: [
          OfficeAccountRecord(
            id: DefaultOfficeAccountIds.mutalib,
            displayName: 'Mutalib',
            status: OfficeAccountStatus.active,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          OfficeAccountRecord(
            id: DefaultOfficeAccountIds.ad,
            displayName: 'AD',
            status: OfficeAccountStatus.active,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        previewAccountIdByOfficeKey: const {
          'mutalib': DefaultOfficeAccountIds.mutalib,
          'ad': DefaultOfficeAccountIds.ad,
        },
      );

      expect(summary.totalReceived, 475000);
      expect(summary.totalSent, 165000);
      expect(summary.pendingCount, 3);
      expect(summary.enteredCount, 1);
      expect(summary.reconciliationCount, 1);
      expect(
        summary.activityForAccountId(DefaultOfficeAccountIds.mutalib).received,
        295000,
      );
      expect(
        summary.activityForAccountId(DefaultOfficeAccountIds.ad).sent,
        75000,
      );
    },
  );

  test('reconciliation keeps the earlier financial values', () {
    final bilal = previewReceipts.singleWhere((receipt) => receipt.id == 'r5');
    final preview = buildReconciliationPreview(
      receipt: bilal,
      newAmount: bilal.amount,
      newParty: bilal.partyName,
      newOfficeAccount: bilal.officeAccount,
    );

    expect(preview.oldAmount, 40000);
    expect(preview.newAmount, 45000);
    expect(preview.oldParty, 'Bilal Ahmed');
    expect(preview.newParty, 'Bilal Ahmed');
    expect(preview.oldOfficeAccount, OfficeAccount.mutalib);
    expect(preview.newOfficeAccount, OfficeAccount.mutalib);
  });

  test('preview receipt ids are unique', () {
    final ids = previewReceipts.map((receipt) => receipt.id).toSet();
    expect(ids.length, previewReceipts.length);
  });
}
