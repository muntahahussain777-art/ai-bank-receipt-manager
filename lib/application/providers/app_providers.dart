import 'package:ai_bank_receipt_manager/application/dashboard/summarize_receipts.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/preview/preview_data.dart';
import 'package:ai_bank_receipt_manager/domain/entities/dashboard_summary.dart';
import 'package:ai_bank_receipt_manager/domain/entities/groq_config_preview.dart';
import 'package:ai_bank_receipt_manager/domain/entities/party.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final previewReceiptsProvider = Provider<List<Receipt>>((ref) {
  return previewReceipts;
});

final previewPartiesProvider = Provider<List<Party>>((ref) {
  return previewParties;
});

final previewGroqConfigsProvider = Provider<List<GroqConfigPreview>>((ref) {
  return previewGroqConfigs;
});

final storedGroqConfigsProvider =
    FutureProvider.autoDispose<List<GroqApiConfigurationRecord>>((ref) async {
      final repo = await ref.watch(groqApiConfigurationRepositoryProvider.future);
      return repo.listActive();
    });

final receiptByIdProvider = Provider.family<Receipt?, String>((ref, id) {
  for (final receipt in ref.watch(previewReceiptsProvider)) {
    if (receipt.id == id) {
      return receipt;
    }
  }
  return null;
});

class SelectedAccountingDate extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime(2026, 10, 10);

  void select(DateTime value) {
    state = dateOnly(value);
  }
}

final selectedAccountingDateProvider =
    NotifierProvider<SelectedAccountingDate, DateTime>(
      SelectedAccountingDate.new,
    );

class VisibleMonth extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime(2026, 10);

  void show(DateTime value) {
    state = DateTime(value.year, value.month);
  }

  void shift(int months) {
    state = DateTime(state.year, state.month + months);
  }
}

final visibleMonthProvider = NotifierProvider<VisibleMonth, DateTime>(
  VisibleMonth.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setMode(ThemeMode mode) {
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

final receiptsForSelectedDateProvider = Provider<List<Receipt>>((ref) {
  final selected = ref.watch(selectedAccountingDateProvider);
  return [
    for (final receipt in ref.watch(previewReceiptsProvider))
      if (isSameDate(receipt.accountingDate, selected)) receipt,
  ];
});

final dailyEntriesProvider = Provider<List<Receipt>>((ref) {
  final receipts = [...ref.watch(receiptsForSelectedDateProvider)];
  receipts.sort((a, b) {
    final byStatus = a.status.deskOrder.compareTo(b.status.deskOrder);
    if (byStatus != 0) {
      return byStatus;
    }
    return a.partyName.compareTo(b.partyName);
  });
  return receipts;
});

final pendingReceiptsProvider = Provider<List<Receipt>>((ref) {
  return [
    for (final receipt in ref.watch(receiptsForSelectedDateProvider))
      if (receipt.status == EntryStatus.pending) receipt,
  ];
});

final enteredReceiptsProvider = Provider<List<Receipt>>((ref) {
  return [
    for (final receipt in ref.watch(receiptsForSelectedDateProvider))
      if (receipt.status == EntryStatus.entered) receipt,
  ];
});

final reconciliationReceiptsProvider = Provider<List<Receipt>>((ref) {
  return [
    for (final receipt in ref.watch(receiptsForSelectedDateProvider))
      if (receipt.status == EntryStatus.needsReconciliation) receipt,
  ];
});

final receiptCountsByDateProvider = Provider<Map<DateTime, int>>((ref) {
  final counts = <DateTime, int>{};
  for (final receipt in ref.watch(previewReceiptsProvider)) {
    final key = dateOnly(receipt.accountingDate);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
});

class OfficeAccountSearch extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final officeAccountSearchProvider =
    NotifierProvider<OfficeAccountSearch, String>(OfficeAccountSearch.new);

class ShowArchivedOfficeAccounts extends Notifier<bool> {
  @override
  bool build() => false;

  void setValue(bool value) => state = value;
}

final showArchivedOfficeAccountsProvider =
    NotifierProvider<ShowArchivedOfficeAccounts, bool>(
      ShowArchivedOfficeAccounts.new,
    );

final officeAccountsProvider =
    FutureProvider.autoDispose<List<OfficeAccountRecord>>((ref) async {
      final repo = await ref.watch(officeAccountRepositoryProvider.future);
      final search = ref.watch(officeAccountSearchProvider);
      final showArchived = ref.watch(showArchivedOfficeAccountsProvider);
      return repo.list(
        includeArchived: showArchived,
        includeInactive: true,
        search: search,
      );
    });

final selectableOfficeAccountsProvider =
    FutureProvider.autoDispose<List<OfficeAccountRecord>>((ref) async {
      final repo = await ref.watch(officeAccountRepositoryProvider.future);
      return repo.listSelectableForNewEntries();
    });

final officeAccountAliasesProvider = FutureProvider.autoDispose
    .family<List<OfficeAccountAliasRecord>, String>((ref, accountId) async {
      final repo = await ref.watch(officeAccountRepositoryProvider.future);
      return repo.listAliases(accountId);
    });

final officeAccountByIdProvider = FutureProvider.autoDispose
    .family<OfficeAccountRecord?, String>((ref, id) async {
      final repo = await ref.watch(officeAccountRepositoryProvider.future);
      return repo.getById(id);
    });

class CustomerSearch extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final customerSearchProvider = NotifierProvider<CustomerSearch, String>(
  CustomerSearch.new,
);

class DealerSearch extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final dealerSearchProvider = NotifierProvider<DealerSearch, String>(
  DealerSearch.new,
);

final storedCustomersProvider =
    FutureProvider.autoDispose<List<CustomerRecord>>((ref) async {
      final repo = await ref.watch(customerRepositoryProvider.future);
      return repo.list(search: ref.watch(customerSearchProvider));
    });

final storedDealersProvider = FutureProvider.autoDispose<List<DealerRecord>>((
  ref,
) async {
  final repo = await ref.watch(dealerRepositoryProvider.future);
  return repo.list(search: ref.watch(dealerSearchProvider));
});

/// Preview parties remain available for Phase 1 desk screens.
final customersProvider = Provider<List<Party>>((ref) {
  return [
    for (final party in ref.watch(previewPartiesProvider))
      if (party.kind == PartyKind.customer) party,
  ];
});

final dealersProvider = Provider<List<Party>>((ref) {
  return [
    for (final party in ref.watch(previewPartiesProvider))
      if (party.kind == PartyKind.dealer) party,
  ];
});

final dashboardSummaryProvider = Provider<DashboardSummary>((ref) {
  final receipts = ref.watch(receiptsForSelectedDateProvider);
  final accountsAsync = ref.watch(officeAccountsProvider);
  final accounts = accountsAsync.maybeWhen(
    data: (value) => value
        .where((account) => account.status != OfficeAccountStatus.archived)
        .toList(),
    orElse: () => const <OfficeAccountRecord>[],
  );

  return summarizeReceiptsForAccounts(
    receipts: receipts,
    accounts: accounts,
    previewAccountIdByOfficeKey: const {
      'mutalib': DefaultOfficeAccountIds.mutalib,
      'ad': DefaultOfficeAccountIds.ad,
    },
  );
});
