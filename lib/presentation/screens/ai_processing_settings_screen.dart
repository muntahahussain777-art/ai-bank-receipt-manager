import 'package:ai_bank_receipt_manager/application/ai/ai_processing_mode.dart';
import 'package:ai_bank_receipt_manager/application/ai/api_test_result.dart';
import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/data/ai/gemini_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final aiProcessingModeProvider = FutureProvider<AiProcessingMode>((ref) async {
  final settings = await ref.watch(aiSettingsServiceProvider.future);
  return settings.getProcessingMode();
});

final offlineFallbackProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(aiSettingsServiceProvider.future);
  return settings.getOfflineFallbackEnabled();
});

/// Premium AI Processing Settings — one active mode at a time.
class AiProcessingSettingsScreen extends ConsumerWidget {
  const AiProcessingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final modeAsync = ref.watch(aiProcessingModeProvider);
    final fallbackAsync = ref.watch(offlineFallbackProvider);
    final configsAsync = ref.watch(storedGroqConfigsProvider);

    return PageScroll(
      children: [
        const SectionHeader(
          title: 'AI Processing Settings',
          subtitle:
              'Choose exactly one processing mode. Cloud providers never run '
              'together. Offline OCR works without API keys.',
        ),
        const SizedBox(height: 12),
        NoticePanel(
          message:
              'API keys stay in Android secure storage — never in reports, '
              'backups, or ordinary logs. Receipt images are sent to a cloud '
              'provider only when that mode is active and you authorize import.',
          icon: Icons.lock_outline,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: modeAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (mode) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Processing Mode', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final option in AiProcessingMode.values)
                  RadioListTile<AiProcessingMode>(
                    value: option,
                    // ignore: deprecated_member_use
                    groupValue: mode,
                    title: Text(option.displayLabel),
                    subtitle: Text(_modeSubtitle(option)),
                    // ignore: deprecated_member_use
                    onChanged: (value) async {
                      if (value == null) {
                        return;
                      }
                      final settings = await ref.read(
                        aiSettingsServiceProvider.future,
                      );
                      await settings.setProcessingMode(value);
                      ref.invalidate(aiProcessingModeProvider);
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: fallbackAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (enabled) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Automatically use Offline OCR when selected AI is unavailable',
              ),
              subtitle: const Text(
                'On quota, network, or model errors — never switches to another '
                'cloud provider.',
              ),
              value: enabled,
              onChanged: (value) async {
                final settings = await ref.read(
                  aiSettingsServiceProvider.future,
                );
                await settings.setOfflineFallbackEnabled(value);
                ref.invalidate(offlineFallbackProvider);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Cloud API keys', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _addKey(context, ref, AiProviderKind.groq),
              icon: const Icon(Icons.add),
              label: const Text('Add Groq key'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _addKey(context, ref, AiProviderKind.gemini),
              icon: const Icon(Icons.add),
              label: const Text('Add Gemini key'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addKey(context, ref, AiProviderKind.custom),
              icon: const Icon(Icons.add),
              label: const Text('Add Custom AI'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        configsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (configs) {
            if (configs.isEmpty) {
              return const EmptyState(
                message:
                    'No cloud keys yet. Offline OCR and Manual Entry still work.',
              );
            }
            return Column(
              children: [
                for (final config in configs) ...[
                  _ProviderCard(
                    config: config,
                    onTestConnection: () =>
                        _runTest(context, ref, config, vision: false),
                    onTestVision: () =>
                        _runTest(context, ref, config, vision: true),
                    onToggle: (v) async {
                      final manager = await ref.read(
                        groqKeyManagerProvider.future,
                      );
                      await manager.setEnabled(id: config.id, enabled: v);
                      ref.invalidate(storedGroqConfigsProvider);
                    },
                    onDelete: () async {
                      final manager = await ref.read(
                        groqKeyManagerProvider.future,
                      );
                      await manager.deleteKey(config.id);
                      ref.invalidate(storedGroqConfigsProvider);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Offline OCR uses on-device Latin text recognition (English / Roman '
          'Urdu). Full Urdu-script OCR is not bundled, to keep the APK small.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  String _modeSubtitle(AiProcessingMode mode) => switch (mode) {
    AiProcessingMode.groq => 'Cloud vision via Groq only',
    AiProcessingMode.gemini => 'Cloud vision via Gemini only',
    AiProcessingMode.custom => 'OpenAI-compatible custom endpoint only',
    AiProcessingMode.offlineOcr => 'Free on-device OCR — zero cloud calls',
    AiProcessingMode.manual => 'No automatic AI or OCR',
  };

  Future<void> _addKey(
    BuildContext context,
    WidgetRef ref,
    AiProviderKind kind,
  ) async {
    final label = TextEditingController(
      text: kind == AiProviderKind.groq
          ? 'Primary Groq'
          : kind == AiProviderKind.gemini
          ? 'Primary Gemini'
          : 'Custom provider',
    );
    final key = TextEditingController();
    final endpoint = TextEditingController(
      text: kind == AiProviderKind.gemini
          ? GeminiConstants.defaultEndpoint
          : GroqConstants.defaultEndpoint,
    );
    final model = ValueNotifier(
      kind == AiProviderKind.gemini
          ? GeminiConstants.defaultVisionModel
          : GroqConstants.defaultVisionModel,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${kind.displayLabel} key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: key,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  helperText: 'Stored securely; never shown fully again.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: endpoint,
                decoration: const InputDecoration(labelText: 'Endpoint'),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: model,
                builder: (context, value, _) {
                  final choices = kind == AiProviderKind.gemini
                      ? GeminiConstants.supportedModelChoices
                      : GroqConstants.supportedModelChoices;
                  return DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: value,
                    decoration: const InputDecoration(labelText: 'Model'),
                    items: [
                      for (final m in choices)
                        DropdownMenuItem(value: m, child: Text(m)),
                      if (kind == AiProviderKind.custom)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        model.value = v;
                      }
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
      ),
    );
    if (saved != true) {
      return;
    }
    final manager = await ref.read(groqKeyManagerProvider.future);
    await manager.addKey(
      label: label.text,
      apiKey: key.text,
      endpoint: endpoint.text,
      modelHint: model.value,
      setPreferred: true,
      providerKind: kind,
    );
    ref.invalidate(storedGroqConfigsProvider);
  }

  Future<void> _runTest(
    BuildContext context,
    WidgetRef ref,
    GroqApiConfigurationRecord config, {
    required bool vision,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Testing API…')),
          ],
        ),
      ),
    );
    try {
      final tester = await ref.read(apiConnectionTesterProvider.future);
      final result = vision
          ? await tester.runVisionTest(config.id)
          : await tester.runConnectionTest(config.id);
      ref.invalidate(storedGroqConfigsProvider);
      if (!context.mounted) {
        return;
      }
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(vision ? 'Vision Test' : 'API Connection'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Provider: ${result.providerLabel}'),
                Text('Model: ${result.model}'),
                Text(
                  'Authentication: ${result.authenticationOk ? 'Successful' : 'Failed'}',
                ),
                Text(
                  'Response: ${result.responseOk ? 'Successful' : 'Failed'}',
                ),
                if (vision)
                  Text(
                    'Vision Support: ${result.visionVerified ? 'Verified' : 'Not verified'}',
                  ),
                const SizedBox(height: 8),
                Text('Status: ${result.status.label}'),
                const SizedBox(height: 8),
                Text(result.explanation),
                if (vision)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Vision tests use a tiny synthetic image and may consume '
                      'a small amount of provider quota.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _runTest(context, ref, config, vision: vision);
              },
              child: const Text('Retry Test'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'AI processing is temporarily unavailable. Please retry or enter '
              'receipt details manually.',
            ),
          ),
        );
      }
    }
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.config,
    required this.onTestConnection,
    required this.onTestVision,
    required this.onToggle,
    required this.onDelete,
  });

  final GroqApiConfigurationRecord config;
  final VoidCallback onTestConnection;
  final VoidCallback onTestVision;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tested = config.lastTestedAt == null
        ? 'Never tested'
        : 'Last test: ${DateFormat('dd MMM yyyy HH:mm').format(config.lastTestedAt!.toLocal())}';
    final status = config.lastTestResult == null
        ? 'Not tested'
        : config.lastTestResult!;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${config.providerKind.displayLabel} · ${config.label}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Switch(value: config.isEnabled, onChanged: onToggle),
            ],
          ),
          Text(config.modelHint ?? 'Default model'),
          Text(config.maskedKeyHint ?? '(key hidden)'),
          Text(tested, style: theme.textTheme.bodySmall),
          Text('Result: $status', style: theme.textTheme.bodySmall),
          if (config.lastTestDetail != null)
            Text(config.lastTestDetail!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: onTestConnection,
                child: const Text('Test API'),
              ),
              OutlinedButton(
                onPressed: onTestVision,
                child: const Text('Vision Test'),
              ),
              TextButton(onPressed: onDelete, child: const Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
