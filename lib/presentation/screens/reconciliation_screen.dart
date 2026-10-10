import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/metric_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ReconciliationScreen extends ConsumerWidget {
  const ReconciliationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedAccountingDateProvider);
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);
    final casesAsync = ref.watch(openReconciliationCasesProvider);
    final summaryAsync = ref.watch(openReconciliationSummaryProvider);

    return PageScroll(
      children: [
        SectionHeader(
          title: 'Needs reconciliation',
          subtitle:
              'Financial changes after Entered for ${formatAccountingDate(date)}. '
              '${BusinessRules.officeEntrySafety}',
        ),
        const SizedBox(height: 12),
        summaryAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (summary) {
            final colors = Theme.of(context).colorScheme;
            return MetricGrid(
              children: [
                MetricCard(
                  label: 'Reconciliation Required',
                  value: formatCount(summary.count),
                  icon: Icons.rule,
                  color: colors.error,
                ),
                MetricCard(
                  label: 'Affected amount',
                  value: formatPkr(summary.affectedAmount),
                  icon: Icons.payments_outlined,
                  color: colors.tertiary,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        casesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (cases) {
            if (cases.isEmpty) {
              return const EmptyState(message: 'No open reconciliation cases.');
            }
            return Column(
              children: [
                for (final item in cases) ...[
                  _CaseCard(caseRecord: item),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: 'Affected receipts',
          subtitle:
              'Open the receipt to view the original image and mark complete.',
        ),
        const SizedBox(height: 12),
        receiptsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (receipts) {
            final rows = [
              for (final r in receipts)
                if (r.status == EntryStatus.needsReconciliation) r,
            ];
            if (rows.isEmpty) {
              return const EmptyState(message: 'No reconciliation items.');
            }
            return Column(
              children: [
                for (final receipt in rows) ...[
                  ReceiptCard(receipt: receipt),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => context.go('/receipts/${receipt.id}'),
                        child: const Text('View differences'),
                      ),
                      OutlinedButton(
                        onPressed: () => context.go('/receipts/${receipt.id}'),
                        child: const Text('View original receipt'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _complete(ref, context, receipt.id),
                        child: const Text('Reconciliation Completed'),
                      ),
                      TextButton(
                        onPressed: () => _reopen(ref, context, receipt.id),
                        child: const Text('Reopen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static Future<void> _complete(
    WidgetRef ref,
    BuildContext context,
    String id,
  ) async {
    final noteController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark office entry correction completed?'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: 'Optional correction notes',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reconciliation Completed'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final service = await ref.read(receiptEntryServiceProvider.future);
    await service.confirmReconciliationReviewed(
      id: id,
      reviewedBy: 'desk',
      correctionNotes: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
    );
    invalidateDeskProviders(ref);
  }

  static Future<void> _reopen(
    WidgetRef ref,
    BuildContext context,
    String id,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen reconciliation?'),
        content: const Text(
          'Creates an audit record and returns this receipt to '
          'Needs Reconciliation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final service = await ref.read(receiptEntryServiceProvider.future);
    await service.reopenReconciliation(id: id, reopenedBy: 'desk');
    invalidateDeskProviders(ref);
  }
}

class _CaseCard extends ConsumerWidget {
  const _CaseCard({required this.caseRecord});

  final ReconciliationCaseRecord caseRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caseRecord.kind.storageValue.replaceAll('_', ' '),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(caseRecord.reason),
          const SizedBox(height: 8),
          Text(
            'Opened ${formatAccountingDate(caseRecord.openedAt)} Â· '
            'Status: ${caseRecord.status.storageValue}',
            style: theme.textTheme.bodySmall,
          ),
          if (caseRecord.previousAmount != null ||
              caseRecord.correctedAmount != null) ...[
            const SizedBox(height: 8),
            Text(
              'Previous: ${formatPkr(caseRecord.previousAmount ?? 0)} â†’ '
              'Corrected: ${formatPkr(caseRecord.correctedAmount ?? 0)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          for (final diff in caseRecord.diffs)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${diff.label}: ${diff.oldValue ?? 'â€”'} â†’ ${diff.newValue ?? 'â€”'}',
              ),
            ),
          if (caseRecord.correctionNotes != null) ...[
            const SizedBox(height: 8),
            Text('Notes: ${caseRecord.correctionNotes}'),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                final controller = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Add correction notes'),
                    content: TextField(controller: controller, maxLines: 3),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (ok != true || controller.text.trim().isEmpty) {
                  return;
                }
                final service = await ref.read(
                  receiptEntryServiceProvider.future,
                );
                await service.addCorrectionNotes(
                  caseId: caseRecord.id,
                  notes: controller.text.trim(),
                  changedBy: 'desk',
                );
                invalidateDeskProviders(ref);
              },
              child: const Text('Add correction notes'),
            ),
          ),
        ],
      ),
    );
  }
}
