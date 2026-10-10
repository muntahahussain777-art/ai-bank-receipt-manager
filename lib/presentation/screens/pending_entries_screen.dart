import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingEntriesScreen extends ConsumerWidget {
  const PendingEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedAccountingDateProvider);
    // Force pending filter for this route without mutating global filter chips.
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);
    final filter = ref.watch(deskListFilterProvider);
    if (filter.statusFilter != EntryStatus.pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(deskListFilterProvider.notifier)
            .setStatus(EntryStatus.pending);
      });
    }

    return PageScroll(
      children: [
        SectionHeader(
          title: 'Pending entries',
          subtitle:
              'Still to type into the office system for ${formatAccountingDate(date)}.',
        ),
        const SizedBox(height: 12),
        receiptsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (receipts) {
            final pending = [
              for (final r in receipts)
                if (r.status == EntryStatus.pending) r,
            ];
            if (pending.isEmpty) {
              return const EmptyState(message: 'No pending receipts.');
            }
            return Column(
              children: [
                for (final receipt in pending) ...[
                  ReceiptCard(receipt: receipt),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
