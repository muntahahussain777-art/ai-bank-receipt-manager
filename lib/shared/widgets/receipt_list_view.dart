import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:flutter/material.dart';

class ReceiptListView extends StatelessWidget {
  const ReceiptListView({
    required this.intro,
    required this.dateLabel,
    required this.receipts,
    required this.emptyMessage,
    super.key,
  });

  final String intro;
  final String dateLabel;
  final List<Receipt> receipts;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageScroll(
      children: [
        const PreviewBanner(),
        const SizedBox(height: 16),
        Text(intro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text(
          dateLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        if (receipts.isEmpty)
          EmptyState(message: emptyMessage)
        else
          ReceiptBoard(receipts: receipts),
      ],
    );
  }
}
