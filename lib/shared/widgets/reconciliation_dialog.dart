import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/domain/entities/reconciliation_preview.dart';
import 'package:ai_bank_receipt_manager/domain/enums/office_account.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:flutter/material.dart';

Future<bool> showReconciliationDialog(
  BuildContext context, {
  required ReconciliationPreview preview,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ReconciliationDialog(preview: preview),
  );
  return result ?? false;
}

class ReconciliationDialog extends StatelessWidget {
  const ReconciliationDialog({required this.preview, super.key});

  final ReconciliationPreview preview;

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
                'Reference ${preview.reference}. The financial values prepared '
                'for manual entry do not match the values now on screen.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('Old financial values', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ValueLine(
                key: const Key('reconciliation-old-amount'),
                label: 'Amount',
                value: formatPkr(preview.oldAmount),
              ),
              _ValueLine(label: 'Customer / dealer', value: preview.oldParty),
              _ValueLine(
                label: 'Office account',
                value: preview.oldOfficeAccount.displayLabel,
              ),
              const SizedBox(height: 16),
              Text('New financial values', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _ValueLine(
                key: const Key('reconciliation-new-amount'),
                label: 'Amount',
                value: formatPkr(preview.newAmount),
              ),
              _ValueLine(label: 'Customer / dealer', value: preview.newParty),
              _ValueLine(
                label: 'Office account',
                value: preview.newOfficeAccount.displayLabel,
              ),
              const SizedBox(height: 16),
              Text('WinForms correction', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                'Enter the corrected amount, party, and office account '
                'manually in WinForms. ${BusinessRules.winFormsSafety} '
                'Confirm only means you have reviewed the difference. '
                'It does not save a record in Phase 1.',
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
          child: const Text('Confirm'),
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
