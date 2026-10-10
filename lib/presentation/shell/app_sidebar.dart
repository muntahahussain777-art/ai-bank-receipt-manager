import 'package:ai_bank_receipt_manager/presentation/shell/app_destination.dart';
import 'package:flutter/material.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
    this.inDrawer = false,
    super.key,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        _Brand(extended: extended || inDrawer),
        const SizedBox(height: 8),
        ..._tiles(theme),
      ],
    );
    final safe = SafeArea(top: inDrawer, bottom: true, child: body);
    if (inDrawer) {
      return safe;
    }
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(width: extended ? 256 : 80, child: safe),
    );
  }

  List<Widget> _tiles(ThemeData theme) {
    final tiles = <Widget>[];
    DestinationGroup? previous;
    for (var index = 0; index < appDestinations.length; index++) {
      final destination = appDestinations[index];
      if (destination.group != previous) {
        previous = destination.group;
        tiles.add(
          extended || inDrawer
              ? _GroupLabel(label: destination.group.label)
              : const Divider(height: 16),
        );
      }
      tiles.add(
        _NavTile(
          destination: destination,
          selected: index == selectedIndex,
          extended: extended || inDrawer,
          onTap: () => onSelected(index),
        ),
      );
    }
    return tiles;
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.account_balance, color: scheme.onPrimary, size: 22),
      ),
    );
    if (!extended) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(child: mark),
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Bank Receipt', style: theme.textTheme.titleMedium),
                Text(
                  'Phase 1 preview',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final tile = Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('nav-${destination.path}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: extended
                ? Row(
                    children: [
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        color: foreground,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          destination.label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: foreground,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
    if (extended) {
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: tile);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(message: destination.label, child: tile),
    );
  }
}
