import 'package:ai_bank_receipt_manager/core/theme/app_theme.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final EntryStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = statusColorsOf(context);
    final (foreground, background) = switch (status) {
      EntryStatus.pending => (colors.pending, colors.pendingContainer),
      EntryStatus.entered => (colors.entered, colors.enteredContainer),
      EntryStatus.needsReconciliation => (
        colors.reconciliation,
        colors.reconciliationContainer,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          status.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}
