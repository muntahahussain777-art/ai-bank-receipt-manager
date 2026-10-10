import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/receipt_card.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CalendarHistoryScreen extends ConsumerWidget {
  const CalendarHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(selectedAccountingDateProvider, (previous, next) {
      final visible = ref.read(visibleMonthProvider);
      if (visible.year != next.year || visible.month != next.month) {
        ref.read(visibleMonthProvider.notifier).show(next);
      }
    });

    final month = ref.watch(visibleMonthProvider);
    final selected = ref.watch(selectedAccountingDateProvider);
    final countsAsync = ref.watch(storedReceiptCountsByMonthProvider);
    final receiptsAsync = ref.watch(storedReceiptsForSelectedDateProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'Calendar and search use stored SQLite receipts. Late receipts '
              'can be assigned to past accounting dates from Import.',
          icon: Icons.history,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search historical receipts',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              ref.read(deskListFilterProvider.notifier).setSearch(value),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SurfaceCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () =>
                            ref.read(visibleMonthProvider.notifier).shift(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          formatMonthYear(month),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () =>
                            ref.read(visibleMonthProvider.notifier).shift(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  countsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e'),
                    data: (counts) => _MonthGrid(
                      month: month,
                      selected: selected,
                      counts: counts,
                      onSelect: (day) {
                        ref
                            .read(selectedAccountingDateProvider.notifier)
                            .select(day);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        receiptsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (receipts) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: formatAccountingDate(selected),
                subtitle: '${receipts.length} stored receipts',
              ),
              const SizedBox(height: 12),
              if (receipts.isEmpty)
                const EmptyState(message: 'No stored receipts on this date.')
              else
                ReceiptBoard(receipts: receipts),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final first = DateTime(month.year, month.month);
    final leading = first.weekday - 1;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = <Widget>[
      for (final label in labels)
        Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= days; day++)
        _DayCell(
          day: DateTime(month.year, month.month, day),
          selected: isSameDate(
            selected,
            DateTime(month.year, month.month, day),
          ),
          count: counts[DateTime(month.year, month.month, day)] ??
              counts[DateTime.utc(month.year, month.month, day)] ??
              0,
          onSelect: onSelect,
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.count,
    required this.onSelect,
  });

  final DateTime day;
  final bool selected;
  final int count;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    return InkWell(
      onTap: () => onSelect(day),
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (count > 0)
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
