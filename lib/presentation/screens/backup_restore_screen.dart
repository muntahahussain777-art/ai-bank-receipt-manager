import 'dart:io';

import 'package:ai_bank_receipt_manager/application/providers/backup_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/data/backup/backup_service.dart';
import 'package:ai_bank_receipt_manager/data/database/db_schema.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  var _busy = false;
  String? _message;
  BackupPreview? _preview;
  final _password = TextEditingController();
  var _encrypt = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageScroll(
      children: [
        SectionHeader(
          title: 'Backup and restore',
          subtitle:
              'Full SQLite + images backup. Groq API keys stay in secure '
              'storage and are never written into a backup. '
              '${BusinessRules.winFormsSafety}',
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create backup', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Encrypt with password (AES-256-GCM)'),
                value: _encrypt,
                onChanged: _busy ? null : (v) => setState(() => _encrypt = v),
              ),
              if (_encrypt)
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Backup password',
                    helperText: 'Minimum 6 characters. Store it safely.',
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _createInternalBackup,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Full backup'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _createExternalBackup,
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text('Save outside app'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _shareLatest,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share backup'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Restore', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Restore verifies integrity, checks schema version, creates a '
                'safety backup, then replaces data only after confirmation.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _pickAndPreview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Select & preview'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _busy || _preview == null || !_preview!.integrityOk
                        ? null
                        : _confirmRestore,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore with confirmation'),
                  ),
                ],
              ),
              if (_preview != null) ...[
                const SizedBox(height: 12),
                Text(
                  _preview!.integrityOk
                      ? 'Integrity OK'
                      : 'Integrity failed: ${_preview!.integrityError}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _preview!.integrityOk
                        ? Colors.green.shade800
                        : theme.colorScheme.error,
                  ),
                ),
                Text(
                  'Created ${formatAccountingDate(_preview!.manifest.createdAt)}',
                ),
                Text(
                  'Schema v${_preview!.manifest.schemaVersion} '
                  '(app v${DbSchema.version})',
                ),
                Text('Size ${_preview!.manifest.fileSizeBytes ?? 0} bytes'),
                Text(
                  'Receipts ${_preview!.manifest.receiptCount} · '
                  'Entered ${_preview!.manifest.enteredCount} · '
                  'Pending ${_preview!.manifest.pendingCount}',
                ),
                Text(
                  'Images ${_preview!.manifest.imageCount} · '
                  'Recon cases ${_preview!.manifest.reconciliationCaseCount}',
                ),
                Text(
                  'Encrypted: ${_preview!.isEncrypted} · '
                  'API keys included: ${_preview!.manifest.includesApiKeys}',
                ),
              ],
            ],
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  Future<BackupService> _service() => ref.read(backupServiceProvider.future);

  Future<void> _createInternalBackup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final service = await _service();
      final result = await service.createFullBackup(
        password: _encrypt ? _password.text : null,
      );
      if (!result.verified) {
        throw StateError('Backup was not verified.');
      }
      setState(() {
        _message =
            'Verified backup saved (${result.manifest.fileSizeBytes} bytes)\n'
            '${result.archivePath}';
      });
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createExternalBackup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Prefer a user-visible downloads / documents location outside app-private.
      Directory? external;
      try {
        external = await getDownloadsDirectory();
      } catch (_) {}
      external ??= await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final ext = _encrypt ? 'aibackup' : 'zip';
      final path = p.join(external.path, 'ai_bank_backup_$stamp.$ext');
      final service = await _service();
      final result = await service.createFullBackup(
        archivePath: path,
        password: _encrypt ? _password.text : null,
      );
      setState(() {
        _message =
            'Verified external backup (${result.manifest.fileSizeBytes} bytes)\n'
            '${result.archivePath}';
      });
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _shareLatest() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final service = await _service();
      final files = await service.listVersionedBackups();
      if (files.isEmpty) {
        throw StateError('No versioned backups found. Create one first.');
      }
      final latest = files.first;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              latest.path,
              mimeType: latest.path.endsWith('.aibackup')
                  ? 'application/octet-stream'
                  : 'application/zip',
            ),
          ],
          text: 'AI Bank Receipt Manager backup',
          subject: p.basename(latest.path),
        ),
      );
      setState(() => _message = 'Share sheet opened for ${latest.path}');
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickAndPreview() async {
    setState(() {
      _busy = true;
      _message = null;
      _preview = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip', 'aibackup'],
      );
      if (picked.isEmpty) {
        return;
      }
      final path = picked.single.path;
      if (path == null) {
        throw StateError('Could not read selected backup path.');
      }
      String? password;
      if (path.endsWith('.aibackup') || _encrypt) {
        password = await _askPassword();
      }
      final service = await _service();
      final preview = await service.inspectArchive(path, password: password);
      setState(() {
        _preview = preview;
        _message = preview.integrityOk
            ? 'Backup ready to restore after confirmation.'
            : 'Preview loaded with errors.';
      });
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmRestore() async {
    final preview = _preview;
    if (preview == null || !preview.integrityOk) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace current data?'),
        content: Text(
          'This will replace all receipts, images, customers, dealers, '
          'office accounts, audit history, and reconciliation cases with the '
          'backup from ${formatAccountingDate(preview.manifest.createdAt)}.\n\n'
          'A safety backup of the current data is created first. '
          'A failed restore leaves current data in place.\n\n'
          'App schema v${DbSchema.version}; backup schema '
          'v${preview.manifest.schemaVersion}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace after safety backup'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      String? password;
      if (preview.isEncrypted) {
        password = await _askPassword();
        if (password == null) {
          return;
        }
      }
      final service = await _service();
      final result = await service.restoreFromArchive(
        archivePath: preview.archivePath,
        confirmReplace: true,
        password: password,
      );
      // Force DB reopen for the rest of the app.
      ref.invalidate(appDatabaseProvider);
      ref.invalidate(receiptRepositoryProvider);
      setState(() {
        _message =
            'Restore verified. Safety copy: ${result.safetyBackupPath}'
            '${result.missingImageCount > 0 ? ' (missing images: ${result.missingImageCount})' : ''}';
      });
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController(text: _password.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result;
  }
}
