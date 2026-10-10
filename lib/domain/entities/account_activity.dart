class AccountActivity {
  const AccountActivity({
    required this.received,
    required this.sent,
    required this.count,
  });

  final double received;
  final double sent;
  final int count;

  static const empty = AccountActivity(received: 0, sent: 0, count: 0);
}
