import 'package:ai_bank_receipt_manager/application/classification/business_classification_service.dart';
import 'package:ai_bank_receipt_manager/application/dashboard/summarize_receipts.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/preview/preview_data.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late OfficeAccountRepository offices;
  late CustomerRepository customers;
  late DealerRepository dealers;
  late ReceiptRepository receipts;

  setUp(() async {
    harness = await TestDbHarness.create();
    offices = OfficeAccountRepository(harness.database);
    customers = CustomerRepository(harness.database);
    dealers = DealerRepository(harness.database);
    receipts = ReceiptRepository(harness.database);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('1 initial Mutalib and AD account creation', () async {
    final accounts = await offices.list();
    expect(accounts.map((a) => a.displayName), containsAll(['Mutalib', 'AD']));
    final mutalib = accounts.firstWhere(
      (a) => a.id == DefaultOfficeAccountIds.mutalib,
    );
    final aliases = await offices.listAliases(mutalib.id);
    expect(aliases.map((a) => a.aliasName), contains('Azlan Traders'));
  });

  test('2 app restart without duplicate seeding', () async {
    await harness.reopen();
    offices = OfficeAccountRepository(harness.database);
    final accounts = await offices.list();
    expect(accounts.where((a) => a.displayName == 'Mutalib').length, 1);
    expect(accounts.where((a) => a.displayName == 'AD').length, 1);
    final settings = AppSettingsRepository(harness.database);
    expect(await settings.get(DefaultOfficeAccountIds.seedFlagKey), '1');
  });

  test('3 add third office account', () async {
    await offices.create(displayName: 'Ahmed', bankAlias: 'Ahmed Enterprises');
    final accounts = await offices.listSelectableForNewEntries();
    expect(accounts.length, 3);
    expect(accounts.map((a) => a.displayName), contains('Ahmed'));
  });

  test('4 add 10 office accounts', () async {
    for (var i = 0; i < 10; i++) {
      await offices.create(displayName: 'Office $i', bankAlias: 'Alias $i');
    }
    expect(await offices.listSelectableForNewEntries(), hasLength(12));
  });

  test('5 rename Mutalib', () async {
    await offices.rename(
      id: DefaultOfficeAccountIds.mutalib,
      displayName: 'Mutalib Desk',
    );
    final renamed = await offices.getById(DefaultOfficeAccountIds.mutalib);
    expect(renamed!.displayName, 'Mutalib Desk');
  });

  test('6 change AD bank alias', () async {
    final aliases = await offices.listAliases(DefaultOfficeAccountIds.ad);
    await offices.removeAlias(aliases.first.id);
    await offices.addAlias(
      accountId: DefaultOfficeAccountIds.ad,
      aliasName: 'Habib Ent.',
    );
    final updated = await offices.listAliases(DefaultOfficeAccountIds.ad);
    expect(updated.map((a) => a.aliasName), contains('Habib Ent.'));
  });

  test('7-9 archive restore and historical receipts remain linked', () async {
    await receipts.appendImport(
      accountingDate: DateTime.utc(2026, 10, 10),
      source: 'phase3',
      drafts: [
        ReceiptImportDraft(
          bankName: 'HBL',
          amount: 1000,
          mappedAccountId: DefaultOfficeAccountIds.mutalib,
          transactionId: 'KEEP-1',
        ),
      ],
    );
    await offices.archive(DefaultOfficeAccountIds.mutalib);
    var mutalib = await offices.getById(DefaultOfficeAccountIds.mutalib);
    expect(mutalib!.status, OfficeAccountStatus.archived);
    expect(
      (await offices.listSelectableForNewEntries()).map((a) => a.id),
      isNot(contains(DefaultOfficeAccountIds.mutalib)),
    );

    await offices.restore(DefaultOfficeAccountIds.mutalib);
    mutalib = await offices.getById(DefaultOfficeAccountIds.mutalib);
    expect(mutalib!.status, OfficeAccountStatus.active);
    expect(
      await offices.countLinkedReceipts(DefaultOfficeAccountIds.mutalib),
      1,
    );
  });

  test('10-11 customer to new office and office to dealer', () async {
    final ahmed = await offices.create(
      displayName: 'Ahmed',
      bankAlias: 'Ahmed Enterprises',
    );
    final customer = await customers.create(
      name: 'Ali Ahmed',
      usualAccountId: ahmed.id,
    );
    final dealer = await dealers.create(
      name: 'Dealer XYZ',
      usualAccountId: ahmed.id,
    );

    final service = BusinessClassificationService();
    final aliases = {ahmed.id: await offices.listAliases(ahmed.id)};
    final incoming = service.classify(
      input: const ClassificationInput(
        bankSenderName: 'Ali Ahmed',
        bankReceiverName: 'Ahmed Enterprises',
        adminMessage: 'Ali Ahmed ne Ahmed ke paas paise lagaye',
      ),
      accounts: [ahmed],
      accountAliases: aliases,
      customers: [customer],
      customerAliases: const {},
      dealers: [dealer],
      dealerAliases: const {},
    );
    expect(incoming.proposedReceiptType, DbReceiptType.received);
    expect(incoming.officeAccountId, ahmed.id);

    final outgoing = service.classify(
      input: const ClassificationInput(
        bankSenderName: 'Ahmed Enterprises',
        bankReceiverName: 'Dealer XYZ',
      ),
      accounts: [ahmed],
      accountAliases: aliases,
      customers: [customer],
      customerAliases: const {},
      dealers: [dealer],
      dealerAliases: const {},
    );
    expect(outgoing.proposedReceiptType, DbReceiptType.sent);
    expect(outgoing.officeAccountId, ahmed.id);
  });

  test('12 unknown account needs review', () async {
    final result = BusinessClassificationService().classify(
      input: const ClassificationInput(
        bankSenderName: 'Random Person',
        bankReceiverName: 'Unknown Bank Title',
      ),
      accounts: await offices.listSelectableForNewEntries(),
      accountAliases: {
        for (final account in await offices.list())
          account.id: await offices.listAliases(account.id),
      },
      customers: const [],
      customerAliases: const {},
      dealers: const [],
      dealerAliases: const {},
    );
    expect(result.needsReview, isTrue);
    expect(result.officeAccountId, isNull);
  });

  test('13 ambiguous aliases do not auto-choose', () async {
    final one = await offices.create(
      displayName: 'Alpha',
      bankAlias: 'Shared Traders',
    );
    final two = await offices.create(
      displayName: 'Beta',
      bankAlias: 'Shared Traders',
    );
    final result = BusinessClassificationService().classify(
      input: const ClassificationInput(bankReceiverName: 'Shared Traders'),
      accounts: [one, two],
      accountAliases: {
        one.id: await offices.listAliases(one.id),
        two.id: await offices.listAliases(two.id),
      },
      customers: const [],
      customerAliases: const {},
      dealers: const [],
      dealerAliases: const {},
    );
    expect(result.needsReview, isTrue);
    expect(result.officeAccountSuggestions.length, greaterThanOrEqualTo(2));
  });

  test('14 conflicting admin note needs review', () async {
    final mutalib = await offices.getById(DefaultOfficeAccountIds.mutalib);
    final ad = await offices.getById(DefaultOfficeAccountIds.ad);
    final result = BusinessClassificationService().classify(
      input: const ClassificationInput(
        bankReceiverName: 'Azlan Traders',
        adminMessage: 'Ali Ahmed ne AD ke paas paise lagaye',
      ),
      accounts: [mutalib!, ad!],
      accountAliases: {
        mutalib.id: await offices.listAliases(mutalib.id),
        ad.id: await offices.listAliases(ad.id),
      },
      customers: const [],
      customerAliases: const {},
      dealers: const [],
      dealerAliases: const {},
    );
    expect(result.needsReview, isTrue);
    expect(
      result.reasons.any((r) => r.toLowerCase().contains('conflict')),
      isTrue,
    );
  });

  test('15 database migration keeps rows', () async {
    await receipts.appendImport(
      accountingDate: DateTime.utc(2026, 10, 1),
      source: 'mig',
      drafts: [harness.draft(transactionId: 'MIG-P3', amount: 11)],
    );
    final db = await harness.database.database;
    expect(DbSchema.version, 5);
    final info = await db.rawQuery(
      'PRAGMA table_info(${DbSchema.officeAccountAliases})',
    );
    expect(info, isNotEmpty);
    final aiInfo = await db.rawQuery(
      'PRAGMA table_info(${DbSchema.aiExtractions})',
    );
    expect(aiInfo, isNotEmpty);
    await harness.reopen();
    receipts = ReceiptRepository(harness.database);
    expect(await receipts.countByAccountingDate(DateTime.utc(2026, 10, 1)), 1);
  });

  test('16-17 entered ticks and audit history remain unchanged', () async {
    await receipts.appendImport(
      accountingDate: DateTime.utc(2026, 10, 10),
      source: 'status',
      drafts: [harness.draft(transactionId: 'ENT-1', amount: 50)],
    );
    final id = (await receipts.listByAccountingDate(
      DateTime.utc(2026, 10, 10),
    )).single.id;
    await receipts.markEntered(id: id, enteredBy: 'desk');
    await receipts.updateReceipt(
      updated: (await receipts.getById(id))!.copyWith(notes: 'checked'),
      changedBy: 'desk',
    );
    final beforeAudit = await receipts.listAuditHistory(id);
    await offices.rename(
      id: DefaultOfficeAccountIds.mutalib,
      displayName: 'Mutalib Renamed',
    );
    final after = await receipts.getById(id);
    expect(after!.entryStatus, DbEntryStatus.entered);
    final afterAudit = await receipts.listAuditHistory(id);
    expect(afterAudit.length, beforeAudit.length);
  });

  test('18-19 delete unused allowed; linked receipts block delete', () async {
    final unused = await offices.create(displayName: 'Temp Unused');
    await offices.permanentlyDelete(
      id: unused.id,
      confirmPermanentDelete: true,
    );
    expect(await offices.getById(unused.id), isNull);

    await receipts.appendImport(
      accountingDate: DateTime.utc(2026, 10, 10),
      source: 'block',
      drafts: [
        ReceiptImportDraft(
          bankName: 'UBL',
          amount: 20,
          mappedAccountId: DefaultOfficeAccountIds.ad,
        ),
      ],
    );
    await expectLater(
      offices.permanentlyDelete(
        id: DefaultOfficeAccountIds.ad,
        confirmPermanentDelete: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('dashboard summary works for any office account list', () {
    final summary = summarizeReceiptsForAccounts(
      receipts: previewReceipts
          .where((r) => r.accountingDate == DateTime(2026, 10, 10))
          .toList(),
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
    expect(
      summary.activityForAccountId(DefaultOfficeAccountIds.mutalib).received,
      295000,
    );
    expect(summary.accountActivities, hasLength(2));
  });

  test('preview entered statuses still present in sample desk data', () {
    final entered = previewReceipts.where(
      (r) => r.status == EntryStatus.entered,
    );
    expect(entered, isNotEmpty);
  });
}
