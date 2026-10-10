import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/core/theme/app_theme.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
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
    final summaryAsync = ref.watch(dailyDeskSummaryProvider);
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);
    final accountsAsync = ref.watch(selectableOfficeAccountsProvider);
    final colors = statusColorsOf(context);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message: BusinessRules.liveDataBanner,
          icon: Icons.info_outline,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        Text('Selected accounting date', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(formatAccountingDate(date), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Desk totals for this date from your saved local records. '
          'Office account cards update when you add or rename accounts.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        summaryAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Unable to load desk totals: $e'),
          data: (summary) => MetricGrid(
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
              MetricCard(
                label: 'Total Receipts',
                value: formatCount(summary.totalCount),
                icon: Icons.receipt_long,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Office account activity',
          subtitle: 'Confirmed office attributions for this accounting date.',
        ),
        const SizedBox(height: 12),
        accountsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Office accounts unavailable: $error'),
          data: (accounts) => summaryAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (summary) => _AccountActivityList(
              activities: _buildActivities(accounts, summary),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: 'Reconciliation required',
          subtitle:
              'Open cases with original vs corrected values. '
              'Complete only after the office entry is corrected by hand.',
        ),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) {
            final casesAsync = ref.watch(openReconciliationCasesProvider);
            final reconSummary = ref.watch(openReconciliationSummaryProvider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                reconSummary.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (s) => Text(
                    '${s.count} open · affected ${formatPkr(s.affectedAmount)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                casesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                  data: (cases) {
                    if (cases.isEmpty) {
                      return const Text('No open reconciliation cases.');
                    }
                    return Column(
                      children: [
                        for (final c in cases) ...[
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.reason,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Previous ${formatPkr(c.previousAmount ?? 0)} → '
                                  'Corrected ${formatPkr(c.correctedAmount ?? 0)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Opened ${formatAccountingDate(c.openedAt)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextButton(
                          onPressed: () => context.go('/reconciliation'),
                          child: const Text('Open reconciliation desk'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        receiptsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Unable to load receipts: $e'),
          data: (receipts) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Receipts on this date',
                subtitle: receipts.isEmpty
                    ? 'No saved receipts yet for this date.'
                    : '${receipts.length} saved receipt(s)',
              ),
              const SizedBox(height: 12),
              if (receipts.isEmpty)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No receipts for ${formatAccountingDate(date)}.',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Import a WhatsApp screenshot or add a manual entry '
                        'to get started.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () => context.go('/import'),
                        child: const Text('Import receipts'),
                      ),
                    ],
                  ),
                )
              else
                ReceiptBoard(receipts: receipts),
            ],
          ),
        ),
      ],
    );
  }

  List<OfficeAccountActivity> _buildActivities(
    List<OfficeAccountRecord> accounts,
    DailyDeskSummary summary,
  ) {
    return [
      for (final account in accounts)
        OfficeAccountActivity(
          account: account,
          received: summary.receivedByAccountId[account.id] ?? 0,
          sent: summary.sentByAccountId[account.id] ?? 0,
          count: summary.countByAccountId[account.id] ?? 0,
        ),
    ];
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
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activity.account.displayName,
            style: theme.textTheme.titleMedium,
          ),
          if (activity.primaryAlias != null) ...[
            const SizedBox(height: 2),
            Text(activity.primaryAlias!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text('${activity.count} receipt(s)'),
          Text(
            'Received ${formatPkr(activity.received)}',
            style: TextStyle(color: colors.received),
          ),
          Text(
            'Sent ${formatPkr(activity.sent)}',
            style: TextStyle(color: colors.sent),
          ),
        ],
      ),
    );
  }
}
