/// Normalizes names for alias suggestion matching. Never auto-merges entities.
String normalizeAlias(String input) {
  var value = input.trim().toLowerCase();
  value = value.replaceAll(RegExp(r'[^\w\s]'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();

  const endings = <String>[
    ' traders',
    ' trading',
    ' enterprises',
    ' enterprise',
    ' petroleum',
    ' pvt ltd',
    ' private limited',
    ' ltd',
    ' limited',
  ];
  for (final ending in endings) {
    if (value.endsWith(ending) && value.length > ending.length + 2) {
      value = value.substring(0, value.length - ending.length).trim();
      break;
    }
  }

  // Common singular/plural trader spelling.
  if (value.endsWith(' traders')) {
    value = '${value.substring(0, value.length - 8)} trader';
  } else if (value.endsWith(' trader')) {
    // keep
  }

  return value;
}

bool aliasesLookSimilar(String a, String b) {
  final left = normalizeAlias(a);
  final right = normalizeAlias(b);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  if (left == right) {
    return true;
  }

  final leftTokens = left.split(' ');
  final rightTokens = right.split(' ');

  // Do not treat "Ali Ahmed" as a fuzzy match for office display name "Ahmed".
  if (leftTokens.length == 1 || rightTokens.length == 1) {
    return false;
  }

  if (left.contains(right) || right.contains(left)) {
    final shorter = left.length < right.length ? left : right;
    return shorter.length >= 3;
  }
  return false;
}
