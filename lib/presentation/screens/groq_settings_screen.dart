import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GroqSettingsScreen extends ConsumerWidget {
  const GroqSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(storedGroqConfigsProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'API keys are stored in Android secure storage only — never in '
              'SQLite or source code. Screenshots are uploaded to Groq only '
              'after you authorize each import. For multi-user distribution, '
              'route keys through a backend proxy.',
          icon: Icons.lock_outline,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _addKeyDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add API key'),
        ),
        const SizedBox(height: 16),
        configsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (configs) {
            if (configs.isEmpty) {
              return const EmptyState(
                message:
                    'No Groq keys yet. Add an enabled key to process receipts.',
              );
            }
            return Column(
              children: [
                for (final config in configs) ...[
                  _KeyCard(
                    config: config,
                    onRename: () => _renameDialog(context, ref, config),
                    onTest: () => _testKey(context, ref, config),
                    onToggleEnabled: (value) async {
                      final manager = await ref.read(
                        groqKeyManagerProvider.future,
                      );
                      await manager.setEnabled(id: config.id, enabled: value);
                      ref.invalidate(storedGroqConfigsProvider);
                    },
                    onPrefer: () async {
                      final manager = await ref.read(
                        groqKeyManagerProvider.future,
                      );
                      await manager.setPreferred(config.id);
                      ref.invalidate(storedGroqConfigsProvider);
                    },
                    onModel: () => _modelDialog(context, ref, config),
                    onDelete: () => _deleteKey(context, ref, config),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _addKeyDialog(BuildContext context, WidgetRef ref) async {
    final labelController = TextEditingController(text: 'Primary');
    final keyController = TextEditingController();
    var setPreferred = true;
    final model = ValueNotifier(GroqConstants.defaultVisionModel);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Groq API key'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyController,
                  decoration: const InputDecoration(
                    labelText: 'API key',
                    helperText:
                        'Stored in secure storage; never shown fully again.',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: model,
                  builder: (context, value, _) {
                    return DropdownButtonFormField<String>(
                      initialValue: value,
                      decoration: const InputDecoration(
                        labelText: 'Vision model',
                      ),
                      items: [
                        for (final choice
                            in GroqConstants.supportedModelChoices)
                          DropdownMenuItem(value: choice, child: Text(choice)),
                      ],
                      onChanged: (next) {
                        if (next != null) {
                          model.value = next;
                        }
                      },
                    );
                  },
                ),
                StatefulBuilder(
                  builder: (context, setState) {
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Set as preferred key'),
                      value: setPreferred,
                      onChanged: (value) {
                        setState(() => setPreferred = value ?? false);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      labelController.dispose();
      keyController.dispose();
      model.dispose();
      return;
    }

    try {
      final manager = await ref.read(groqKeyManagerProvider.future);
      await manager.addKey(
        label: labelController.text,
        apiKey: keyController.text,
        modelHint: model.value,
        setPreferred: setPreferred,
      );
      ref.invalidate(storedGroqConfigsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API key saved to secure storage.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      labelController.dispose();
      keyController.dispose();
      model.dispose();
    }
  }

  Future<void> _renameDialog(
    BuildContext context,
    WidgetRef ref,
    GroqApiConfigurationRecord config,
  ) async {
    final controller = TextEditingController(text: config.label);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename key'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      final manager = await ref.read(groqKeyManagerProvider.future);
      await manager.rename(id: config.id, label: controller.text);
      ref.invalidate(storedGroqConfigsProvider);
    }
    controller.dispose();
  }

  Future<void> _modelDialog(
    BuildContext context,
    WidgetRef ref,
    GroqApiConfigurationRecord config,
  ) async {
    var selected = config.modelHint ?? GroqConstants.defaultVisionModel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Vision model'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: [
              for (final choice in GroqConstants.supportedModelChoices)
                DropdownMenuItem(value: choice, child: Text(choice)),
            ],
            onChanged: (value) {
              if (value != null) {
                selected = value;
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      final manager = await ref.read(groqKeyManagerProvider.future);
      await manager.updateModel(id: config.id, model: selected);
      ref.invalidate(storedGroqConfigsProvider);
    }
  }

  Future<void> _testKey(
    BuildContext context,
    WidgetRef ref,
    GroqApiConfigurationRecord config,
  ) async {
    try {
      final manager = await ref.read(groqKeyManagerProvider.future);
      await manager.testKey(config.id);
      ref.invalidate(storedGroqConfigsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Key "${config.label}" tested OK.')),
        );
      }
    } on GroqFailure catch (failure) {
      ref.invalidate(storedGroqConfigsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _deleteKey(
    BuildContext context,
    WidgetRef ref,
    GroqApiConfigurationRecord config,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete key'),
          content: Text(
            'Remove "${config.label}" (${config.maskedKeyHint ?? 'masked'}) '
            'from secure storage?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      final manager = await ref.read(groqKeyManagerProvider.future);
      await manager.deleteKey(config.id);
      ref.invalidate(storedGroqConfigsProvider);
    }
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.config,
    required this.onRename,
    required this.onTest,
    required this.onToggleEnabled,
    required this.onPrefer,
    required this.onModel,
    required this.onDelete,
  });

  final GroqApiConfigurationRecord config;
  final VoidCallback onRename;
  final VoidCallback onTest;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onPrefer;
  final VoidCallback onModel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(config.label, style: theme.textTheme.titleMedium),
              ),
              if (config.isActive)
                Chip(
                  label: const Text('Preferred'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Key: ${config.maskedKeyHint ?? '(none)'}'),
          const SizedBox(height: 4),
          Text(
            'Model: ${config.modelHint ?? GroqConstants.defaultVisionModel}',
          ),
          const SizedBox(height: 4),
          Text('Endpoint: ${config.endpoint}'),
          if (config.lastErrorStatus != null) ...[
            const SizedBox(height: 4),
            Text(
              'Recent error: ${config.lastErrorStatus}'
              '${config.lastErrorAt == null ? '' : ' · ${config.lastErrorAt!.toLocal()}'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (config.lastTestedAt != null) ...[
            const SizedBox(height: 4),
            Text('Last tested: ${config.lastTestedAt!.toLocal()}'),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled for fallback'),
            value: config.isEnabled,
            onChanged: onToggleEnabled,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onRename, child: const Text('Rename')),
              OutlinedButton(onPressed: onTest, child: const Text('Test')),
              OutlinedButton(
                onPressed: config.isActive ? null : onPrefer,
                child: const Text('Prefer'),
              ),
              OutlinedButton(onPressed: onModel, child: const Text('Model')),
              TextButton(onPressed: onDelete, child: const Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
