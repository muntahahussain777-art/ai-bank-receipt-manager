import 'package:ai_bank_receipt_manager/application/desk/receipt_desk_mapper.dart';
import 'package:ai_bank_receipt_manager/application/desk/receipt_entry_service.dart';
import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final receiptEntryServiceProvider = FutureProvider<ReceiptEntryService>((
  ref,
) async {
  final receipts = await ref.watch(receiptRepositoryProvider.future);
  return ReceiptEntryService(receipts);
});

class DeskListFilterState {
  const DeskListFilterState({
    this.bankName,
    this.mappedAccountId,
    this.customerId,
    this.dealerId,
    this.statusFilter,
    this.searchText = '',
    this.dateFrom,
    this.dateTo,
  });

  final String? bankName;
  final String? mappedAccountId;
  final String? customerId;
  final String? dealerId;

  /// null = all; pending/entered/recon map to SQL filters.
  final EntryStatus? statusFilter;
  final String searchText;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  DeskListFilterState copyWith({
    String? bankName,
    String? mappedAccountId,
    String? customerId,
    String? dealerId,
    EntryStatus? statusFilter,
    String? searchText,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearBank = false,
    bool clearAccount = false,
    bool clearCustomer = false,
    bool clearDealer = false,
    bool clearStatus = false,
    bool clearDateRange = false,
  }) {
    return DeskListFilterState(
      bankName: clearBank ? null : (bankName ?? this.bankName),
      mappedAccountId: clearAccount
          ? null
          : (mappedAccountId ?? this.mappedAccountId),
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      dealerId: clearDealer ? null : (dealerId ?? this.dealerId),
      statusFilter: clearStatus ? null : (statusFilter ?? this.statusFilter),
      searchText: searchText ?? this.searchText,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
    );
  }
}

class DeskListFilterController extends Notifier<DeskListFilterState> {
  @override
  DeskListFilterState build() => const DeskListFilterState();

  void setBank(String? value) =>
      state = state.copyWith(bankName: value, clearBank: value == null);

  void setAccount(String? value) => state = state.copyWith(
    mappedAccountId: value,
    clearAccount: value == null,
  );

  void setCustomer(String? value) => state = state.copyWith(
    customerId: value,
    clearCustomer: value == null,
  );

  void setDealer(String? value) =>
      state = state.copyWith(dealerId: value, clearDealer: value == null);

  void setStatus(EntryStatus? value) => state = state.copyWith(
    statusFilter: value,
    clearStatus: value == null,
  );

  void setSearch(String value) => state = state.copyWith(searchText: value);

  void setDateRange(DateTime? from, DateTime? to) => state = state.copyWith(
    dateFrom: from,
    dateTo: to,
    clearDateRange: from == null && to == null,
  );

  void clear() => state = const DeskListFilterState();
}

final deskListFilterProvider =
    NotifierProvider<DeskListFilterController, DeskListFilterState>(
      DeskListFilterController.new,
    );

final dailyDeskSummaryProvider =
    FutureProvider.autoDispose<DailyDeskSummary>((ref) async {
      final repo = await ref.watch(receiptRepositoryProvider.future);
      final date = ref.watch(selectedAccountingDateProvider);
      return repo.summarizeAccountingDate(date);
    });

final storedReceiptsForSelectedDateProvider =
    FutureProvider.autoDispose<List<Receipt>>((ref) async {
      final repo = await ref.watch(receiptRepositoryProvider.future);
      final customers = await ref.watch(customerRepositoryProvider.future);
      final dealers = await ref.watch(dealerRepositoryProvider.future);
      final offices = await ref.watch(officeAccountRepositoryProvider.future);
      final date = ref.watch(selectedAccountingDateProvider);
      final filter = ref.watch(deskListFilterProvider);

      final records = await repo.listFiltered(
        ReceiptListFilter(
          accountingDate: filter.dateFrom == null && filter.dateTo == null
              ? date
              : null,
          accountingDateFrom: filter.dateFrom,
          accountingDateTo: filter.dateTo,
          bankName: filter.bankName,
          mappedAccountId: filter.mappedAccountId,
          customerId: filter.customerId,
          dealerId: filter.dealerId,
          entryStatus: switch (filter.statusFilter) {
            EntryStatus.pending => DbEntryStatus.pending,
            EntryStatus.entered => DbEntryStatus.entered,
            _ => null,
          },
          reviewStatus: filter.statusFilter == EntryStatus.needsReconciliation
              ? DbReviewStatus.needsReconciliation
              : null,
          searchText: filter.searchText.isEmpty ? null : filter.searchText,
        ),
      );

      final filtered = <ReceiptRecord>[];
      for (final record in records) {
        switch (filter.statusFilter) {
          case EntryStatus.pending:
            if (record.entryStatus == DbEntryStatus.pending &&
                record.reviewStatus != DbReviewStatus.needsReconciliation) {
              filtered.add(record);
            }
          case EntryStatus.entered:
            if (record.entryStatus == DbEntryStatus.entered &&
                record.reviewStatus != DbReviewStatus.needsReconciliation) {
              filtered.add(record);
            }
          case EntryStatus.needsReconciliation:
            if (record.reviewStatus == DbReviewStatus.needsReconciliation) {
              filtered.add(record);
            }
          case null:
            filtered.add(record);
        }
      }

      final officeList = await offices.list(includeInactive: true);
      final officeById = {for (final o in officeList) o.id: o};
      final customerList = await customers.list();
      final customerById = {for (final c in customerList) c.id: c};
      final dealerList = await dealers.list();
      final dealerById = {for (final d in dealerList) d.id: d};

      final mapped = [
        for (final record in filtered)
          ReceiptDeskMapper.toDomain(
            record,
            partyName: record.customerId != null
                ? customerById[record.customerId!]?.name
                : record.dealerId != null
                ? dealerById[record.dealerId!]?.name
                : null,
            partyKind: record.dealerId != null
                ? PartyKind.dealer
                : PartyKind.customer,
            officeAccount: record.mappedAccountId == null
                ? null
                : officeById[record.mappedAccountId!],
            officeAccountLabel: record.mappedAccountId == null
                ? null
                : officeById[record.mappedAccountId!]?.displayName,
          ),
      ];

      mapped.sort((a, b) {
        final byStatus = a.status.deskOrder.compareTo(b.status.deskOrder);
        if (byStatus != 0) {
          return byStatus;
        }
        return a.partyName.compareTo(b.partyName);
      });
      return mapped;
    });

final storedReceiptByIdProvider =
    FutureProvider.autoDispose.family<Receipt?, String>((ref, id) async {
      final repo = await ref.watch(receiptRepositoryProvider.future);
      final record = await repo.getById(id);
      if (record == null) {
        return null;
      }
      final offices = await ref.watch(officeAccountRepositoryProvider.future);
      final customers = await ref.watch(customerRepositoryProvider.future);
      final dealers = await ref.watch(dealerRepositoryProvider.future);
      final office = record.mappedAccountId == null
          ? null
          : await offices.getById(record.mappedAccountId!);
      final customer = record.customerId == null
          ? null
          : await customers.getById(record.customerId!);
      final dealer = record.dealerId == null
          ? null
          : await dealers.getById(record.dealerId!);
      return ReceiptDeskMapper.toDomain(
        record,
        partyName: customer?.name ?? dealer?.name,
        partyKind: dealer != null ? PartyKind.dealer : PartyKind.customer,
        officeAccount: office,
        officeAccountLabel: office?.displayName,
      );
    });

final storedReceiptCountsByMonthProvider =
    FutureProvider.autoDispose<Map<DateTime, int>>((ref) async {
      final repo = await ref.watch(receiptRepositoryProvider.future);
      final month = ref.watch(visibleMonthProvider);
      final from = DateTime(month.year, month.month, 1);
      final to = DateTime(month.year, month.month + 1, 0);
      return repo.countByAccountingDateRange(from: from, to: to);
    });

void invalidateDeskProviders(WidgetRef ref) {
  ref.invalidate(storedReceiptsForSelectedDateProvider);
  ref.invalidate(dailyDeskSummaryProvider);
  ref.invalidate(storedReceiptCountsByMonthProvider);
}
