import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    return PageScroll(
      children: [
        const PreviewBanner(),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'The theme choice lasts until the app closes. It is not written to storage.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              RadioGroup<ThemeMode>(
                groupValue: mode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(themeModeProvider.notifier).setMode(value);
                  }
                },
                child: Column(
                  children: const [
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('System'),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Light'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Dark'),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Office rules', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final rule in BusinessRules.rules) ...[
                Text(rule),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About this build', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('AI Bank Receipt Manager'),
              const Text('Phase 1 preview shell'),
              const Text('Version 0.1.0'),
              const Text('Android'),
              const SizedBox(height: 8),
              Text(
                'This phase does not call the network, store receipts, or change WinForms.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
