import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/account_mask.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/status_chip.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccountMappingScreen extends ConsumerWidget {
  const AccountMappingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(officeAccountsProvider);
    final showArchived = ref.watch(showArchivedOfficeAccountsProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'Office accounts are stored in SQLite and can be added, renamed, '
              'aliased, archived, or restored. Defaults Mutalib and AD are '
              'editable records, not permanent identities. '
              '${BusinessRules.winFormsSafety}',
          icon: Icons.account_balance_outlined,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _showUpsertDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
            FilterChip(
              label: Text(showArchived ? 'Hide archived' : 'Show archived'),
              selected: showArchived,
              onSelected: (value) {
                ref
                    .read(showArchivedOfficeAccountsProvider.notifier)
                    .setValue(value);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search accounts or aliases',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            ref.read(officeAccountSearchProvider.notifier).setQuery(value);
          },
        ),
        const SizedBox(height: 16),
        accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Could not load office accounts: $error'),
          data: (accounts) {
            if (accounts.isEmpty) {
              return const EmptyState(
                message: 'No office accounts match this search.',
              );
            }
            return Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _OfficeAccountCard(account: accounts[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class OfficeAccountDetailsScreen extends ConsumerWidget {
  const OfficeAccountDetailsScreen({required this.accountId, super.key});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(officeAccountByIdProvider(accountId));
    final aliasesAsync = ref.watch(officeAccountAliasesProvider(accountId));

    return PageScroll(
      children: [
        accountAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('$error'),
          data: (account) {
            if (account == null) {
              return const EmptyState(message: 'Office account not found.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: account.displayName,
                  subtitle: account.status.storageValue,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          _showUpsertDialog(context, ref, existing: account),
                      child: const Text('Edit / rename'),
                    ),
                    if (account.status == OfficeAccountStatus.archived)
                      FilledButton.tonal(
                        onPressed: () async {
                          final repo = await ref.read(
                            officeAccountRepositoryProvider.future,
                          );
                          await repo.restore(account.id);
                          ref.invalidate(officeAccountsProvider);
                          ref.invalidate(officeAccountByIdProvider(accountId));
                        },
                        child: const Text('Restore'),
                      )
                    else ...[
                      OutlinedButton(
                        onPressed: () async {
                          final confirmed = await _confirm(
                            context,
                            title: 'Archive office account?',
                            message:
                                'Receipts stay linked to this account UUID. '
                                'It will not be offered for new entries.',
                          );
                          if (!confirmed) {
                            return;
                          }
                          final repo = await ref.read(
                            officeAccountRepositoryProvider.future,
                          );
                          await repo.archive(account.id);
                          ref.invalidate(officeAccountsProvider);
                          ref.invalidate(officeAccountByIdProvider(accountId));
                        },
                        child: const Text('Archive'),
                      ),
                      if (account.status == OfficeAccountStatus.active)
                        OutlinedButton(
                          onPressed: () async {
                            final repo = await ref.read(
                              officeAccountRepositoryProvider.future,
                            );
                            await repo.deactivate(account.id);
                            ref.invalidate(officeAccountsProvider);
                            ref.invalidate(
                              officeAccountByIdProvider(accountId),
                            );
                          },
                          child: const Text('Deactivate'),
                        )
                      else
                        OutlinedButton(
                          onPressed: () async {
                            final repo = await ref.read(
                              officeAccountRepositoryProvider.future,
                            );
                            await repo.activate(account.id);
                            ref.invalidate(officeAccountsProvider);
                            ref.invalidate(
                              officeAccountByIdProvider(accountId),
                            );
                          },
                          child: const Text('Activate'),
                        ),
                    ],
                    TextButton(
                      onPressed: () =>
                          _tryPermanentDelete(context, ref, account),
                      child: const Text('Delete if unused'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Bank aliases',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                aliasesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('$error'),
                  data: (aliases) {
                    return Column(
                      children: [
                        for (final alias in aliases)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(alias.aliasName),
                            subtitle: Text(alias.approvalStatus.storageValue),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final repo = await ref.read(
                                  officeAccountRepositoryProvider.future,
                                );
                                await repo.removeAlias(alias.id);
                                ref.invalidate(
                                  officeAccountAliasesProvider(accountId),
                                );
                              },
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _addAlias(context, ref, accountId),
                          icon: const Icon(Icons.add),
                          label: const Text('Add alias'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Linked receipt history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                FutureBuilder(
                  future: ref
                      .read(officeAccountRepositoryProvider.future)
                      .then((repo) => repo.listLinkedReceiptRows(accountId)),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final rows = snapshot.data!;
                    if (rows.isEmpty) {
                      return const Text(
                        'No linked receipts yet. Historical links remain if receipts are mapped later.',
                      );
                    }
                    return Column(
                      children: [
                        for (final row in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${row['bank_name']} · ${formatPkr((row['amount'] as num).toDouble())}',
                            ),
                            subtitle: Text(
                              'Accounting ${row['accounting_date']} · '
                              '${row['entry_status']} · ${row['transaction_id'] ?? '—'}',
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OfficeAccountCard extends ConsumerWidget {
  const _OfficeAccountCard({required this.account});

  final OfficeAccountRecord account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliasesAsync = ref.watch(officeAccountAliasesProvider(account.id));
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  account.displayName,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              InfoPill(label: account.status.storageValue),
            ],
          ),
          const SizedBox(height: 8),
          aliasesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (aliases) {
              if (aliases.isEmpty) {
                return Text(
                  'No bank aliases yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Text(
                aliases
                    .map((alias) => maskAccountNumber(alias.aliasName))
                    .join(' · '),
                style: theme.textTheme.bodyLarge,
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => context.push('/mapping/${account.id}'),
                child: const Text('Details'),
              ),
              FilledButton.tonal(
                onPressed: () =>
                    _showUpsertDialog(context, ref, existing: account),
                child: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showUpsertDialog(
  BuildContext context,
  WidgetRef ref, {
  OfficeAccountRecord? existing,
}) async {
  final nameController = TextEditingController(
    text: existing?.displayName ?? '',
  );
  final aliasController = TextEditingController();
  final notesController = TextEditingController(text: existing?.notes ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          existing == null ? 'Add office account' : 'Edit office account',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              if (existing == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: aliasController,
                  decoration: const InputDecoration(
                    labelText: 'Bank alias (optional)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
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

  if (saved != true || !context.mounted) {
    nameController.dispose();
    aliasController.dispose();
    notesController.dispose();
    return;
  }

  final repo = await ref.read(officeAccountRepositoryProvider.future);
  if (existing == null) {
    await repo.create(
      displayName: nameController.text,
      bankAlias: aliasController.text,
      notes: notesController.text.trim().isEmpty ? null : notesController.text,
    );
  } else {
    await repo.rename(id: existing.id, displayName: nameController.text);
  }
  ref.invalidate(officeAccountsProvider);
  if (existing != null) {
    ref.invalidate(officeAccountByIdProvider(existing.id));
  }
  nameController.dispose();
  aliasController.dispose();
  notesController.dispose();
}

Future<void> _addAlias(
  BuildContext context,
  WidgetRef ref,
  String accountId,
) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Add bank alias'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Alias name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      );
    },
  );
  if (ok == true) {
    final repo = await ref.read(officeAccountRepositoryProvider.future);
    await repo.addAlias(accountId: accountId, aliasName: controller.text);
    ref.invalidate(officeAccountAliasesProvider(accountId));
  }
  controller.dispose();
}

Future<void> _tryPermanentDelete(
  BuildContext context,
  WidgetRef ref,
  OfficeAccountRecord account,
) async {
  final repo = await ref.read(officeAccountRepositoryProvider.future);
  final receipts = await repo.countLinkedReceipts(account.id);
  final parties = await repo.countLinkedParties(account.id);
  if (!context.mounted) {
    return;
  }
  if (receipts > 0 || parties > 0) {
    await showPhaseNotice(
      context,
      title: 'Delete blocked',
      message:
          'This account still has $receipts linked receipt(s) and $parties '
          'linked customer/dealer row(s). Archive it instead. Receipt history '
          'is never cascade-deleted.',
    );
    return;
  }
  final confirmed = await _confirm(
    context,
    title: 'Permanently delete account?',
    message:
        'Only unused accounts can be deleted. This cannot be undone. '
        'Deleted defaults are never recreated automatically.',
  );
  if (!confirmed) {
    return;
  }
  await repo.permanentlyDelete(id: account.id, confirmPermanentDelete: true);
  ref.invalidate(officeAccountsProvider);
  if (context.mounted) {
    context.go('/mapping');
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
