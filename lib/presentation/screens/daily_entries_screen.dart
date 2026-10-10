import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DailyEntriesScreen extends ConsumerStatefulWidget {
  const DailyEntriesScreen({super.key});

  @override
  ConsumerState<DailyEntriesScreen> createState() => _DailyEntriesScreenState();
}

class _DailyEntriesScreenState extends ConsumerState<DailyEntriesScreen> {
  final _selected = <String>{};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedAccountingDateProvider);
    final summaryAsync = ref.watch(dailyDeskSummaryProvider);
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);
    final filter = ref.watch(deskListFilterProvider);
    final officesAsync = ref.watch(selectableOfficeAccountsProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'Mark Entered only after typing into WinForms. Ticks persist '
              'across later imports. Financial edits on Entered rows require '
              'reconciliation and never clear the tick silently.',
          icon: Icons.checklist_outlined,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 12),
        Text(
          'Selected accounting date: ${formatAccountingDate(date)}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        summaryAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (summary) =>
              _SummaryStrip(summary: summary, officesAsync: officesAsync),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search bank, reference, admin note…',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              ref.read(deskListFilterProvider.notifier).setSearch(value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('All'),
              selected: filter.statusFilter == null,
              onSelected: (_) =>
                  ref.read(deskListFilterProvider.notifier).setStatus(null),
            ),
            FilterChip(
              label: const Text('Pending'),
              selected: filter.statusFilter == EntryStatus.pending,
              onSelected: (_) => ref
                  .read(deskListFilterProvider.notifier)
                  .setStatus(EntryStatus.pending),
            ),
            FilterChip(
              label: const Text('Entered'),
              selected: filter.statusFilter == EntryStatus.entered,
              onSelected: (_) => ref
                  .read(deskListFilterProvider.notifier)
                  .setStatus(EntryStatus.entered),
            ),
            FilterChip(
              label: const Text('Reconciliation'),
              selected:
                  filter.statusFilter == EntryStatus.needsReconciliation,
              onSelected: (_) => ref
                  .read(deskListFilterProvider.notifier)
                  .setStatus(EntryStatus.needsReconciliation),
            ),
            OutlinedButton(
              onPressed: _selected.isEmpty ? null : _bulkMarkEntered,
              child: Text('Bulk Entered (${_selected.length})'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Daily list',
          subtitle: 'Desk order: pending → reconciliation → entered.',
        ),
        const SizedBox(height: 12),
        receiptsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (receipts) {
            if (receipts.isEmpty) {
              return const EmptyState(
                message: 'No stored receipts for this filter / date.',
              );
            }
            return Column(
              children: [
                for (final receipt in receipts) ...[
                  ReceiptCard(
                    receipt: receipt,
                    selected: _selected.contains(receipt.id),
                    onSelectedChanged: receipt.entryStatusEntered
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selected.add(receipt.id);
                              } else {
                                _selected.remove(receipt.id);
                              }
                            });
                          },
                    onEnteredChanged: (value) =>
                        _toggleEntered(receipt.id, value),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _toggleEntered(String id, bool? value) async {
    final service = await ref.read(receiptEntryServiceProvider.future);
    try {
      if (value == true) {
        await service.markEntered(id: id, enteredBy: 'desk');
      } else {
        if (!mounted) {
          return;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Undo Entered?'),
            content: const Text(
              'Only undo if the WinForms row was not kept. This does not '
              'change WinForms.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Undo Entered'),
              ),
            ],
          ),
        );
        if (ok != true) {
          return;
        }
        await service.undoEntered(
          id: id,
          confirmed: true,
          changedBy: 'desk',
        );
      }
      invalidateDeskProviders(ref);
      ref.invalidate(storedReceiptByIdProvider(id));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _bulkMarkEntered() async {
    final service = await ref.read(receiptEntryServiceProvider.future);
    try {
      await service.markEnteredBulk(
        ids: _selected.toList(),
        enteredBy: 'desk',
      );
      setState(() => _selected.clear());
      invalidateDeskProviders(ref);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.officesAsync});

  final DailyDeskSummary summary;
  final AsyncValue<List<OfficeAccountRecord>> officesAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Metric('Total', '${summary.totalCount}'),
              _Metric('Received', formatPkr(summary.totalReceived)),
              _Metric('Sent', formatPkr(summary.totalSent)),
              _Metric('Pending', '${summary.pendingCount}'),
              _Metric('Entered', '${summary.enteredCount}'),
              _Metric('Reconciliation', '${summary.reconciliationCount}'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Office accounts', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          officesAsync.maybeWhen(
            data: (offices) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final office in offices)
                    Chip(
                      label: Text(
                        '${office.displayName}: '
                        '${summary.countByAccountId[office.id] ?? 0} txn · '
                        'in ${formatPkr(summary.receivedByAccountId[office.id] ?? 0)} · '
                        'out ${formatPkr(summary.sentByAccountId[office.id] ?? 0)}',
                      ),
                    ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
