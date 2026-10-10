/// Parses informal WhatsApp admin notes (English / Roman Urdu / mixed)
/// for accounting attribution hints. Never invents missing names.
abstract final class AdminNoteParser {
  /// Candidate person/business names mentioned as the accounting party.
  static List<String> extractAttributionNames(String? adminMessage) {
    if (adminMessage == null || adminMessage.trim().isEmpty) {
      return const [];
    }
    final text = adminMessage.trim();
    final found = <String>[];

    final patterns = <RegExp>[
      // "Ye Rashid ke paise hain" / "Rashid ke paise"
      RegExp(
        r'(?:ye|yh|yeh)?\s*([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40}?)\s+ke\s+paise',
        caseSensitive: false,
      ),
      // "Ali Ahmed nill" / "Ali Ahmed nil"
      RegExp(
        r'^([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40}?)\s+nill?\b',
        caseSensitive: false,
      ),
      // "Ye Bilal dealer ko diya hai"
      RegExp(
        r'(?:ye|yh|yeh)?\s*([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40}?)\s+dealer',
        caseSensitive: false,
      ),
      // "Ahmed ke account mein jama"
      RegExp(
        r'([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40}?)\s+ke\s+account',
        caseSensitive: false,
      ),
      // "… mein Rashid ke paise aaye"
      RegExp(
        r'mein\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40}?)\s+ke\s+paise',
        caseSensitive: false,
      ),
      // "payment for Rashid" / "for Rashid"
      RegExp(
        r'(?:payment\s+)?for\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40})',
        caseSensitive: false,
      ),
      // "customer Rashid" / "dealer Bilal"
      RegExp(
        r'(?:customer|dealer)\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{1,40})',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final name = _cleanName(match.group(1));
        if (name != null &&
            !found.any((n) => n.toLowerCase() == name.toLowerCase())) {
          found.add(name);
        }
      }
    }
    return found;
  }

  /// True when note mentions dealer attribution.
  static bool suggestsDealer(String? adminMessage) {
    if (adminMessage == null) {
      return false;
    }
    final lower = adminMessage.toLowerCase();
    return lower.contains('dealer') ||
        lower.contains('ko diya') ||
        lower.contains('bheja');
  }

  static String? _cleanName(String? raw) {
    if (raw == null) {
      return null;
    }
    var name = raw.trim();
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    // Drop leading filler words.
    name = name.replaceFirst(
      RegExp(r'^(ye|yh|yeh|the|a|an)\s+', caseSensitive: false),
      '',
    );
    if (name.length < 2 || name.length > 48) {
      return null;
    }
    // Reject pure office keywords.
    final lower = name.toLowerCase();
    if (lower == 'mutalib' ||
        lower == 'ad' ||
        lower == 'paise' ||
        lower == 'payment') {
      return null;
    }
    return name;
  }
}
