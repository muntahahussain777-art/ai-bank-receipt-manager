import 'package:flutter/material.dart';

enum DestinationGroup {
  work('Work'),
  status('Status'),
  directory('Directory'),
  system('System');

  const DestinationGroup(this.label);

  final String label;
}

class AppDestination {
  const AppDestination({
    required this.label,
    required this.title,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.group,
  });

  final String label;
  final String title;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final DestinationGroup group;
}

const appDestinations = <AppDestination>[
  AppDestination(
    label: 'Dashboard',
    title: 'Dashboard',
    path: '/dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    group: DestinationGroup.work,
  ),
  AppDestination(
    label: 'Import',
    title: 'Import receipts',
    path: '/import',
    icon: Icons.add_photo_alternate_outlined,
    selectedIcon: Icons.add_photo_alternate,
    group: DestinationGroup.work,
  ),
  AppDestination(
    label: 'Daily entries',
    title: 'Daily entries',
    path: '/daily',
    icon: Icons.view_list_outlined,
    selectedIcon: Icons.view_list,
    group: DestinationGroup.work,
  ),
  AppDestination(
    label: 'Calendar',
    title: 'Calendar / history',
    path: '/calendar',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    group: DestinationGroup.work,
  ),
  AppDestination(
    label: 'Pending',
    title: 'Pending entries',
    path: '/pending',
    icon: Icons.hourglass_empty,
    selectedIcon: Icons.hourglass_bottom,
    group: DestinationGroup.status,
  ),
  AppDestination(
    label: 'Entered',
    title: 'Entered entries',
    path: '/entered',
    icon: Icons.task_alt_outlined,
    selectedIcon: Icons.task_alt,
    group: DestinationGroup.status,
  ),
  AppDestination(
    label: 'Reconciliation',
    title: 'Reconciliation required',
    path: '/reconciliation',
    icon: Icons.rule_folder_outlined,
    selectedIcon: Icons.rule_folder,
    group: DestinationGroup.status,
  ),
  AppDestination(
    label: 'Customers',
    title: 'Customers',
    path: '/customers',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    group: DestinationGroup.directory,
  ),
  AppDestination(
    label: 'Dealers',
    title: 'Dealers',
    path: '/dealers',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping,
    group: DestinationGroup.directory,
  ),
  AppDestination(
    label: 'Office accounts',
    title: 'Office accounts',
    path: '/mapping',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    group: DestinationGroup.directory,
  ),
  AppDestination(
    label: 'AI Processing',
    title: 'AI Processing Settings',
    path: '/groq',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    group: DestinationGroup.system,
  ),
  AppDestination(
    label: 'Reports',
    title: 'Reports',
    path: '/reports',
    icon: Icons.summarize_outlined,
    selectedIcon: Icons.summarize,
    group: DestinationGroup.system,
  ),
  AppDestination(
    label: 'Backup',
    title: 'Backup and restore',
    path: '/backup',
    icon: Icons.backup_outlined,
    selectedIcon: Icons.backup,
    group: DestinationGroup.system,
  ),
  AppDestination(
    label: 'Settings',
    title: 'General settings',
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    group: DestinationGroup.system,
  ),
];

int indexForLocation(String path) {
  final direct = appDestinations.indexWhere((item) => item.path == path);
  if (direct >= 0) {
    return direct;
  }
  if (path.startsWith('/receipts/')) {
    return appDestinations.indexWhere((item) => item.path == '/daily');
  }
  if (path.startsWith('/mapping/')) {
    return appDestinations.indexWhere((item) => item.path == '/mapping');
  }
  return 0;
}

String titleForLocation(String path) {
  if (path.startsWith('/receipts/')) {
    return 'Receipt details';
  }
  if (path.startsWith('/mapping/')) {
    return 'Office account details';
  }
  for (final destination in appDestinations) {
    if (destination.path == path) {
      return destination.title;
    }
  }
  return 'AI Bank Receipt Manager';
}
