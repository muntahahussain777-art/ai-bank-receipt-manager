import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

class BackupRestoreScreen extends StatelessWidget {
  const BackupRestoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const included = <String>[
      'Receipt records',
      'Receipt images',
      'Customer and dealer directory',
      'Account mapping',
      'Audit history',
    ];
    const restoreRules = <String>[
      'Restore must ask before replacing the current data.',
      'A backup of the current data must exist before restore replaces it.',
      'A failed restore must leave the current data in place.',
    ];
    final theme = Theme.of(context);
    return PageScroll(
      children: [
        const PreviewBanner(),
        const SizedBox(height: 16),
        Text(
          'Full database and image backup is a later phase. This screen does not copy or replace any files.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A future backup includes',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final item in included) Text('• $item'),
              const SizedBox(height: 12),
              Text(
                'Groq API keys stay in secure storage and are not written into a plain backup.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Safe restore, required later',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final rule in restoreRules) ...[
                Text(rule),
                const SizedBox(height: 6),
              ],
              Text(BusinessRules.winFormsSafety),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => showPhaseNotice(
                context,
                title: 'Backup is not available',
                message:
                    'Phase 1 does not copy the database or images. No file was created.',
              ),
              child: const Text('Backup is not in Phase 1'),
            ),
            OutlinedButton(
              onPressed: () => showPhaseNotice(
                context,
                title: 'Restore is not available',
                message:
                    'Phase 1 does not read or replace any backup. No data was changed.',
              ),
              child: const Text('Restore is not in Phase 1'),
            ),
          ],
        ),
      ],
    );
  }
}
