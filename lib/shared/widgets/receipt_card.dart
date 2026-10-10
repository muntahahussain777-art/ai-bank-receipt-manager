import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/enums/bank_direction.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_flow.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/status_chip.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({
    required this.receipt,
    this.selected = false,
    this.onSelectedChanged,
    this.onEnteredChanged,
    super.key,
  });

  final Receipt receipt;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;
  final ValueChanged<bool?>? onEnteredChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onSelectedChanged != null)
                Checkbox(value: selected, onChanged: onSelectedChanged),
              _BankMark(name: receipt.bankName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(receipt.bankName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      receipt.reference,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEnteredChanged != null)
                Column(
                  children: [
                    const Text('Entered'),
                    Checkbox(
                      value: receipt.entryStatusEntered,
                      onChanged: onEnteredChanged,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            formatPkr(receipt.amount),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(status: receipt.status),
              InfoPill(label: receipt.bankDirection.label),
              InfoPill(label: receipt.officeFlow.label),
            ],
          ),
          const SizedBox(height: 12),
          _Fact(label: 'Sender', value: receipt.bankSenderName ?? '—'),
          _Fact(label: 'Receiver', value: receipt.bankReceiverName ?? '—'),
          _Fact(label: receipt.partyKind.label, value: receipt.partyName),
          _Fact(label: 'Office account', value: receipt.officeDisplayLabel),
          _Fact(
            label: 'Accounting date',
            value: formatAccountingDate(receipt.accountingDate),
          ),
          _Fact(label: 'Reference', value: receipt.reference),
          if (receipt.winformsReference != null)
            _Fact(label: 'WinForms ref', value: receipt.winformsReference!),
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Admin note: ${receipt.adminNote.isEmpty ? '—' : receipt.adminNote}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/receipts/${receipt.id}'),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View'),
              ),
              if (receipt.originalImagePath != null)
                OutlinedButton.icon(
                  onPressed: () => context.push('/receipts/${receipt.id}'),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Original'),
                ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    context.push('/receipts/${receipt.id}?edit=true'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReceiptBoard extends StatelessWidget {
  const ReceiptBoard({required this.receipts, super.key});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var i = 0; i < receipts.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                ReceiptCard(receipt: receipts[i]),
              ],
            ],
          );
        }
        final left = <Receipt>[];
        final right = <Receipt>[];
        for (var i = 0; i < receipts.length; i++) {
          (i.isEven ? left : right).add(receipts[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _column(left)),
            const SizedBox(width: 12),
            Expanded(child: _column(right)),
          ],
        );
      },
    );
  }

  Widget _column(List<Receipt> items) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          ReceiptCard(receipt: items[i]),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BankMark extends StatelessWidget {
  const _BankMark({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Text(
            letter,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
