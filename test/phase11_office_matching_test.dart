import 'dart:io';

import 'package:ai_bank_receipt_manager/application/classification/admin_note_parser.dart';
import 'package:ai_bank_receipt_manager/application/classification/business_classification_service.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db_harness.dart';

void main() {
  late TestDbHarness harness;
  late OfficeAccountRepository offices;
  late CustomerRepository customers;
  late DealerRepository dealers;

  setUp(() async {
    harness = await TestDbHarness.create();
    offices = OfficeAccountRepository(harness.database);
    customers = CustomerRepository(harness.database);
    dealers = DealerRepository(harness.database);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('admin note parses Roman Urdu customer attribution', () {
    expect(
      AdminNoteParser.extractAttributionNames('Ye Rashid ke paise hain'),
      contains('Rashid'),
    );
    expect(
      AdminNoteParser.extractAttributionNames('Ali Ahmed nill'),
      contains('Ali Ahmed'),
    );
    expect(
      AdminNoteParser.suggestsDealer('Ye Bilal dealer ko diya hai'),
      isTrue,
    );
  });

  test(
    'TEST1 Ali Ahmed → Azlan Traders + Rashid admin note → Mutalib incoming',
    () async {
      final rashid = await customers.create(name: 'Rashid');
      await customers.addAlias(
        customerId: rashid.id,
        aliasName: 'Rashid',
        approvalStatus: AliasApprovalStatus.approved,
      );

      final accounts = await offices.listSelectableForNewEntries();
      final aliases = <String, List<OfficeAccountAliasRecord>>{};
      for (final a in accounts) {
        aliases[a.id] = await offices.listAliases(a.id);
      }

      final result = BusinessClassificationService().classify(
        input: const ClassificationInput(
          bankSenderName: 'Ali Ahmed',
          bankReceiverName: 'Azlan Traders',
          adminMessage: 'Ye Rashid ke paise hain',
          whatsappSender: 'Mujtaba',
          bankDirectionHint: DbReceiptType.received,
        ),
        accounts: accounts,
        accountAliases: aliases,
        customers: [rashid],
        customerAliases: {rashid.id: await customers.listAliases(rashid.id)},
        dealers: const [],
        dealerAliases: const {},
      );

      expect(result.officeAccountId, DefaultOfficeAccountIds.mutalib);
      expect(result.proposedReceiptType, DbReceiptType.received);
      expect(result.customerId, rashid.id);
      expect(result.suggestedCustomerName, 'Rashid');
      expect(result.customerConfirmationRequired, isTrue);
    },
  );

  test('TEST2 Habib Enterprise → Dealer XYZ → AD outgoing', () async {
    final dealer = await dealers.create(name: 'Dealer XYZ');
    await dealers.addAlias(
      dealerId: dealer.id,
      aliasName: 'Dealer XYZ',
      approvalStatus: AliasApprovalStatus.approved,
    );

    final accounts = await offices.listSelectableForNewEntries();
    final aliases = <String, List<OfficeAccountAliasRecord>>{};
    for (final a in accounts) {
      aliases[a.id] = await offices.listAliases(a.id);
    }

    final result = BusinessClassificationService().classify(
      input: const ClassificationInput(
        bankSenderName: 'Habib Enterprise',
        bankReceiverName: 'Dealer XYZ',
        adminMessage: 'Dealer XYZ payment',
      ),
      accounts: accounts,
      accountAliases: aliases,
      customers: const [],
      customerAliases: const {},
      dealers: [dealer],
      dealerAliases: {dealer.id: await dealers.listAliases(dealer.id)},
    );

    expect(result.officeAccountId, DefaultOfficeAccountIds.ad);
    expect(result.proposedReceiptType, DbReceiptType.sent);
    expect(result.dealerId, dealer.id);
  });

  test('TEST3 new office account alias works without hardcoding', () async {
    final created = await offices.create(displayName: 'New Desk');
    await offices.addAlias(
      accountId: created.id,
      aliasName: 'Nova Traders',
      approvalStatus: AliasApprovalStatus.approved,
    );

    final accounts = await offices.listSelectableForNewEntries();
    final aliases = <String, List<OfficeAccountAliasRecord>>{};
    for (final a in accounts) {
      aliases[a.id] = await offices.listAliases(a.id);
    }

    final result = BusinessClassificationService().classify(
      input: const ClassificationInput(
        bankSenderName: 'Customer One',
        bankReceiverName: 'Nova Traders',
      ),
      accounts: accounts,
      accountAliases: aliases,
      customers: const [],
      customerAliases: const {},
      dealers: const [],
      dealerAliases: const {},
    );

    expect(result.officeAccountId, created.id);
    expect(result.proposedReceiptType, DbReceiptType.received);
  });

  test('user-facing UI strings avoid SQLite/WinForms/Flutter terms', () {
    final offenders = <String>[];
    for (final rootPath in ['lib/presentation', 'lib/shared']) {
      final root = Directory(rootPath);
      if (!root.existsSync()) {
        continue;
      }
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final text = entity.readAsStringSync();
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
            continue;
          }
          if (trimmed.contains('SQLite') ||
              trimmed.contains('WinForms') ||
              trimmed.contains("'Flutter") ||
              trimmed.contains('"Flutter')) {
            offenders.add('${entity.path}: $trimmed');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
