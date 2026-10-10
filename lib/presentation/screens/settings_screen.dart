import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/backup_providers.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  var _lockEnabled = false;
  var _biometric = false;
  String? _lockMessage;

  @override
  void initState() {
    super.initState();
    _loadLock();
  }

  Future<void> _loadLock() async {
    final lock = ref.read(appLockServiceProvider);
    final enabled = await lock.isEnabled();
    final biometric = await lock.biometricEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _lockEnabled = enabled;
      _biometric = biometric;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                'Theme preference for this session.',
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
                child: const Column(
                  children: [
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
              Text('App lock', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Optional PIN or biometric lock. PIN is stored only as a hash '
                'in platform secure storage.',
                style: theme.textTheme.bodyMedium,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_lockEnabled ? 'Lock enabled' : 'Lock disabled'),
                value: _lockEnabled,
                onChanged: (value) async {
                  if (value) {
                    await _enableLock();
                  } else {
                    await _disableLock();
                  }
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow biometric unlock'),
                value: _biometric,
                onChanged: !_lockEnabled
                    ? null
                    : (value) async {
                        await ref
                            .read(appLockServiceProvider)
                            .setBiometricEnabled(value);
                        setState(() => _biometric = value);
                      },
              ),
              if (_lockMessage != null) Text(_lockMessage!),
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
              Text('Database schema v${DbSchema.version}'),
              const Text('Version 0.1.0'),
              const Text('Android'),
              const SizedBox(height: 8),
              Text(
                'Groq API keys stay in secure storage. Backups never include '
                'plain-text keys. ${BusinessRules.officeEntrySafety}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _enableLock() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set PIN'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '4-12 digit PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (pin == null) {
      return;
    }
    try {
      await ref.read(appLockServiceProvider).enableWithPin(pin);
      setState(() {
        _lockEnabled = true;
        _lockMessage = 'App lock enabled.';
      });
    } catch (error) {
      setState(() => _lockMessage = '$error');
    }
  }

  Future<void> _disableLock() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm PIN to disable lock'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (pin == null) {
      return;
    }
    try {
      await ref.read(appLockServiceProvider).disable(currentPin: pin);
      setState(() {
        _lockEnabled = false;
        _biometric = false;
        _lockMessage = 'App lock disabled.';
      });
    } catch (error) {
      setState(() => _lockMessage = '$error');
    }
  }
}
