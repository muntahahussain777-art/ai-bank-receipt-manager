import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EnteredEntriesScreen extends ConsumerWidget {
  const EnteredEntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedAccountingDateProvider);
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);

    return PageScroll(
      children: [
        SectionHeader(
          title: 'Entered entries',
          subtitle:
              'Already typed into the office system for ${formatAccountingDate(date)}. '
              'Ticks never clear silently.',
        ),
        const SizedBox(height: 12),
        receiptsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (receipts) {
            final entered = [
              for (final r in receipts)
                if (r.entryStatusEntered) r,
            ];
            if (entered.isEmpty) {
              return const EmptyState(message: 'No entered receipts.');
            }
            return Column(
              children: [
                for (final receipt in entered) ...[
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
