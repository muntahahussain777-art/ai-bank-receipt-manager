import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/presentation/shell/app_destination.dart';
import 'package:ai_bank_receipt_manager/presentation/shell/app_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final extended = width >= 1100;
    final path = GoRouterState.of(context).uri.path;
    final selectedIndex = indexForLocation(path);
    final date = ref.watch(selectedAccountingDateProvider);
    final showBack =
        path.startsWith('/receipts/') || path.startsWith('/mapping/');

    return Scaffold(
      drawer: compact
          ? Drawer(
              child: AppSidebar(
                selectedIndex: selectedIndex,
                extended: true,
                inDrawer: true,
                onSelected: (index) {
                  Navigator.pop(context);
                  context.go(appDestinations[index].path);
                },
              ),
            )
          : null,
      appBar: AppBar(
        title: Text(titleForLocation(path), overflow: TextOverflow.ellipsis),
        leading: showBack
            ? IconButton(
                tooltip: 'Back',
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          if (width >= 520)
            TextButton.icon(
              onPressed: () => _pickDate(context, ref, date),
              icon: const Icon(Icons.event),
              label: Text(formatAccountingDate(date)),
            )
          else
            IconButton(
              tooltip: 'Accounting date ${formatAccountingDate(date)}',
              onPressed: () => _pickDate(context, ref, date),
              icon: const Icon(Icons.event),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          if (!compact)
            AppSidebar(
              selectedIndex: selectedIndex,
              extended: extended,
              onSelected: (index) => context.go(appDestinations[index].path),
            ),
          if (!compact) const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Future<void> _pickDate(
  BuildContext context,
  WidgetRef ref,
  DateTime current,
) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2020),
    lastDate: DateTime(2035),
    helpText: 'Selected accounting date',
  );
  if (picked == null || !context.mounted) {
    return;
  }
  ref.read(selectedAccountingDateProvider.notifier).select(picked);
}
