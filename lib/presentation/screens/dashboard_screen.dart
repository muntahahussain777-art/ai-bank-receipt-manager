import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/core/theme/app_theme.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/metric_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedAccountingDateProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final receipts = ref.watch(dailyEntriesProvider);
    final accountsAsync = ref.watch(officeAccountsProvider);
    final colors = statusColorsOf(context);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        const PreviewBanner(),
        const SizedBox(height: 16),
        Text('Selected accounting date', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(formatAccountingDate(date), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Desk totals for this date. Office account cards load from SQLite '
          'and scale as accounts are added. ${BusinessRules.winFormsSafety}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        MetricGrid(
          children: [
            MetricCard(
              label: 'Total Received',
              value: formatPkr(summary.totalReceived),
              icon: Icons.south_west,
              color: colors.received,
            ),
            MetricCard(
              label: 'Total Sent',
              value: formatPkr(summary.totalSent),
              icon: Icons.north_east,
              color: colors.sent,
            ),
            MetricCard(
              label: 'Pending Entries',
              value: formatCount(summary.pendingCount),
              icon: Icons.hourglass_empty,
              color: colors.pending,
            ),
            MetricCard(
              label: 'Entered Entries',
              value: formatCount(summary.enteredCount),
              icon: Icons.task_alt,
              color: colors.entered,
            ),
            MetricCard(
              label: 'Reconciliation Required',
              value: formatCount(summary.reconciliationCount),
              icon: Icons.rule,
              color: colors.reconciliation,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Office account activity',
          subtitle: 'Loaded from SQLite. Not limited to Mutalib or AD.',
        ),
        const SizedBox(height: 12),
        accountsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Office accounts unavailable: $error'),
          data: (_) =>
              _AccountActivityList(activities: summary.accountActivities),
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: 'Receipts on this date',
          subtitle: '${receipts.length} preview receipts',
        ),
        const SizedBox(height: 12),
        if (receipts.isEmpty)
          const EmptyState(
            message: 'No preview receipts on this accounting date.',
          )
        else
          ReceiptBoard(receipts: receipts),
      ],
    );
  }
}

class _AccountActivityList extends StatelessWidget {
  const _AccountActivityList({required this.activities});

  final List<OfficeAccountActivity> activities;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No active office accounts yet.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/mapping'),
              child: const Text('Manage office accounts'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        if (!wide) {
          return Column(
            children: [
              for (var i = 0; i < activities.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _ActivityCard(activity: activities[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final activity in activities)
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: _ActivityCard(activity: activity),
              ),
          ],
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});

  final OfficeAccountActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = statusColorsOf(context);
    final account = activity.account;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.displayName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            activity.primaryAlias ?? account.status.storageValue,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _MoneyLine(
            label: 'Received',
            value: formatPkr(activity.received),
            color: colors.received,
          ),
          _MoneyLine(
            label: 'Sent',
            value: formatPkr(activity.sent),
            color: colors.sent,
          ),
          const SizedBox(height: 4),
          Text(
            '${activity.count} receipts on this date',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/mapping/${account.id}'),
              child: const Text('Open account'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
