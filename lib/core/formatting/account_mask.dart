/// Masks long digit runs that look like bank account numbers for ordinary UI.
/// Never logs or displays full account numbers in list/detail surfaces.
String maskAccountNumber(String? value) {
  if (value == null || value.trim().isEmpty) {
    return value ?? '';
  }
  return value.replaceAllMapped(RegExp(r'\d{8,}'), (match) {
    final digits = match.group(0)!;
    if (digits.length <= 4) {
      return digits;
    }
    final visible = digits.substring(digits.length - 4);
    return '${'*' * (digits.length - 4)}$visible';
  });
}

/// True when [value] contains a digit run long enough to treat as an account.
bool containsAccountNumber(String? value) {
  if (value == null) {
    return false;
  }
  return RegExp(r'\d{8,}').hasMatch(value);
}
