import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/domain/entities/reconciliation_preview.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:flutter/material.dart';

Future<bool> showReconciliationDialog(
  BuildContext context, {
  required ReconciliationPreview preview,
  String confirmLabel = 'Confirm correction',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ReconciliationDialog(
      preview: preview,
      confirmLabel: confirmLabel,
    ),
  );
  return result ?? false;
}

class ReconciliationDialog extends StatelessWidget {
  const ReconciliationDialog({
    required this.preview,
    this.confirmLabel = 'Confirm correction',
    super.key,
  });

  final ReconciliationPreview preview;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Reconciliation required'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reference ${preview.reference}. This receipt was previously '
                'Entered. Financial values changed and WinForms may still '
                'show the old figures.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('Previous amount', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ValueLine(
                key: const Key('reconciliation-old-amount'),
                label: 'Amount',
                value: formatPkr(preview.oldAmount),
              ),
              const SizedBox(height: 12),
              Text('Corrected amount', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ValueLine(
                key: const Key('reconciliation-new-amount'),
                label: 'Amount',
                value: formatPkr(preview.newAmount),
              ),
              const SizedBox(height: 16),
              Text('Old financial values', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ValueLine(label: 'Customer / dealer', value: preview.oldParty),
              _ValueLine(
                label: 'Office account',
                value: preview.oldOfficeAccount.displayLabel,
              ),
              const SizedBox(height: 16),
              Text('New financial values', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ValueLine(label: 'Customer / dealer', value: preview.newParty),
              _ValueLine(
                label: 'Office account',
                value: preview.newOfficeAccount.displayLabel,
              ),
              if (preview.fieldDiffs.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Changed fields', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final diff in preview.fieldDiffs)
                  _ValueLine(
                    label: diff.label,
                    value: '${diff.oldValue ?? '—'} → ${diff.newValue ?? '—'}',
                  ),
              ],
              const SizedBox(height: 16),
              Text('WinForms correction', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                '${preview.winFormsMessage} ${BusinessRules.winFormsSafety} '
                'Cancel leaves the receipt unchanged.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('reconciliation-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('reconciliation-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
