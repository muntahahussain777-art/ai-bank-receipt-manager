import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReconciliationScreen extends ConsumerWidget {
  const ReconciliationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedAccountingDateProvider);
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);

    return PageScroll(
      children: [
        SectionHeader(
          title: 'Needs reconciliation',
          subtitle:
              'Financial changes after Entered for ${formatAccountingDate(date)}. '
              'Correct WinForms by hand, then clear the warning from details.',
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
