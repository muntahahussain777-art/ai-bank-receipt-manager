import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(storedCustomersProvider);
    final accountsAsync = ref.watch(selectableOfficeAccountsProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'Customers send money to any active office account. '
              'Renaming or archiving a customer never destroys receipt history. '
              '${BusinessRules.officeEntrySafety}',
          icon: Icons.groups_outlined,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _editCustomer(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add customer'),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search customers or aliases',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            ref.read(customerSearchProvider.notifier).setQuery(value);
          },
        ),
        const SizedBox(height: 16),
        customersAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (customers) {
            if (customers.isEmpty) {
              return const EmptyState(message: 'No customers yet.');
            }
            return Column(
              children: [
                for (final customer in customers) ...[
                  _CustomerCard(
                    customer: customer,
                    accountLabel: accountsAsync.maybeWhen(
                      data: (accounts) {
                        for (final account in accounts) {
                          if (account.id == customer.usualAccountId) {
                            return account.displayName;
                          }
                        }
                        return customer.usualAccountId;
                      },
                      orElse: () => customer.usualAccountId,
                    ),
                    onEdit: () =>
                        _editCustomer(context, ref, existing: customer),
                    onArchive: () async {
                      final repo = await ref.read(
                        customerRepositoryProvider.future,
                      );
                      await repo.archive(customer.id);
                      ref.invalidate(storedCustomersProvider);
                    },
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
}

class DealersScreen extends ConsumerWidget {
  const DealersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealersAsync = ref.watch(storedDealersProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'Any active office account can send money to dealers. '
              'Archive keeps history. ${BusinessRules.officeEntrySafety}',
          icon: Icons.local_shipping_outlined,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _editDealer(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add dealer'),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search dealers or aliases',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            ref.read(dealerSearchProvider.notifier).setQuery(value);
          },
        ),
        const SizedBox(height: 16),
        dealersAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (dealers) {
            if (dealers.isEmpty) {
              return const EmptyState(message: 'No dealers yet.');
            }
            return Column(
              children: [
                for (final dealer in dealers) ...[
                  _DealerCard(
                    dealer: dealer,
                    onEdit: () => _editDealer(context, ref, existing: dealer),
                    onArchive: () async {
                      final repo = await ref.read(
                        dealerRepositoryProvider.future,
                      );
                      await repo.archive(dealer.id);
                      ref.invalidate(storedDealersProvider);
                    },
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
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onArchive,
    this.accountLabel,
  });

  final CustomerRecord customer;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final String? accountLabel;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer.name, style: Theme.of(context).textTheme.titleMedium),
          if (accountLabel != null) ...[
            const SizedBox(height: 4),
            Text('Usual office account: $accountLabel'),
          ],
          if (customer.notes != null && customer.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(customer.notes!),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
              TextButton(onPressed: onArchive, child: const Text('Archive')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DealerCard extends StatelessWidget {
  const _DealerCard({
    required this.dealer,
    required this.onEdit,
    required this.onArchive,
  });

  final DealerRecord dealer;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dealer.name, style: Theme.of(context).textTheme.titleMedium),
          if (dealer.notes != null && dealer.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(dealer.notes!),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
              TextButton(onPressed: onArchive, child: const Text('Archive')),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _editCustomer(
  BuildContext context,
  WidgetRef ref, {
  CustomerRecord? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  final alias = TextEditingController();
  String? accountId = existing?.usualAccountId;
  final accounts = await ref.read(selectableOfficeAccountsProvider.future);

  if (!context.mounted) {
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(existing == null ? 'Add customer' : 'Edit customer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Usual office account',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      for (final account in accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.displayName),
                        ),
                    ],
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  if (existing == null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: alias,
                      decoration: const InputDecoration(
                        labelText: 'Alias (optional)',
                      ),
                    ),
                  ],
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
    },
  );

  if (ok == true) {
    final repo = await ref.read(customerRepositoryProvider.future);
    if (existing == null) {
      await repo.create(
        name: name.text,
        usualAccountId: accountId,
        notes: notes.text.trim().isEmpty ? null : notes.text,
        aliases: alias.text.trim().isEmpty ? const [] : [alias.text],
      );
    } else {
      await repo.update(
        CustomerRecord(
          id: existing.id,
          name: name.text,
          usualAccountId: accountId,
          notes: notes.text.trim().isEmpty ? null : notes.text,
          createdAt: existing.createdAt,
          updatedAt: existing.updatedAt,
          deletedAt: existing.deletedAt,
        ),
      );
    }
    ref.invalidate(storedCustomersProvider);
  }
  name.dispose();
  notes.dispose();
  alias.dispose();
}

Future<void> _editDealer(
  BuildContext context,
  WidgetRef ref, {
  DealerRecord? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  final alias = TextEditingController();
  String? accountId = existing?.usualAccountId;
  final accounts = await ref.read(selectableOfficeAccountsProvider.future);

  if (!context.mounted) {
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(existing == null ? 'Add dealer' : 'Edit dealer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Usual office account',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      for (final account in accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.displayName),
                        ),
                    ],
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  if (existing == null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: alias,
                      decoration: const InputDecoration(
                        labelText: 'Alias (optional)',
                      ),
                    ),
                  ],
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
    },
  );

  if (ok == true) {
    final repo = await ref.read(dealerRepositoryProvider.future);
    if (existing == null) {
      await repo.create(
        name: name.text,
        usualAccountId: accountId,
        notes: notes.text.trim().isEmpty ? null : notes.text,
        aliases: alias.text.trim().isEmpty ? const [] : [alias.text],
      );
    } else {
      await repo.update(
        DealerRecord(
          id: existing.id,
          name: name.text,
          usualAccountId: accountId,
          notes: notes.text.trim().isEmpty ? null : notes.text,
          createdAt: existing.createdAt,
          updatedAt: existing.updatedAt,
          deletedAt: existing.deletedAt,
        ),
      );
    }
    ref.invalidate(storedDealersProvider);
  }
  name.dispose();
  notes.dispose();
  alias.dispose();
}
