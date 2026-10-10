import 'dart:convert';

/// Structured extraction. Null means the model did not clearly see the value.
class ReceiptExtraction {
  const ReceiptExtraction({
    this.bankName,
    this.senderBankAccountName,
    this.receiverBankAccountName,
    this.amount,
    this.currency,
    this.transactionReference,
    this.transactionDateTimeRaw,
    this.whatsappSender,
    this.adminMessage,
    this.maskedAccountNumbers = const [],
    this.uncertainFields = const [],
    this.missingFields = const [],
    this.fieldConfidence = const {},
    this.overallConfidence,
    this.modelNotes,
  });

  final String? bankName;
  final String? senderBankAccountName;
  final String? receiverBankAccountName;
  final double? amount;
  final String? currency;
  final String? transactionReference;
  final String? transactionDateTimeRaw;
  final String? whatsappSender;
  final String? adminMessage;
  final List<String> maskedAccountNumbers;
  final List<String> uncertainFields;
  final List<String> missingFields;
  final Map<String, double> fieldConfidence;
  final double? overallConfidence;
  final String? modelNotes;

  Map<String, Object?> toJson() => {
    'bankName': bankName,
    'senderBankAccountName': senderBankAccountName,
    'receiverBankAccountName': receiverBankAccountName,
    'amount': amount,
    'currency': currency,
    'transactionReference': transactionReference,
    'transactionDateTime': transactionDateTimeRaw,
    'whatsappSender': whatsappSender,
    'adminMessage': adminMessage,
    'maskedAccountNumbers': maskedAccountNumbers,
    'uncertainFields': uncertainFields,
    'missingFields': missingFields,
    'fieldConfidence': fieldConfidence,
    'overallConfidence': overallConfidence,
    'notes': modelNotes,
  };

  String toJsonString() => jsonEncode(toJson());
}

enum ExtractionParseStatus { ok, malformed, schemaInvalid }

class ExtractionParseResult {
  const ExtractionParseResult._({
    required this.status,
    this.extraction,
    this.errorMessage,
    this.rawJson,
  });

  factory ExtractionParseResult.ok(ReceiptExtraction extraction, String raw) {
    return ExtractionParseResult._(
      status: ExtractionParseStatus.ok,
      extraction: extraction,
      rawJson: raw,
    );
  }

  factory ExtractionParseResult.malformed(String message, [String? raw]) {
    return ExtractionParseResult._(
      status: ExtractionParseStatus.malformed,
      errorMessage: message,
      rawJson: raw,
    );
  }

  factory ExtractionParseResult.schemaInvalid(String message, [String? raw]) {
    return ExtractionParseResult._(
      status: ExtractionParseStatus.schemaInvalid,
      errorMessage: message,
      rawJson: raw,
    );
  }

  final ExtractionParseStatus status;
  final ReceiptExtraction? extraction;
  final String? errorMessage;
  final String? rawJson;

  bool get isOk => status == ExtractionParseStatus.ok && extraction != null;
}

/// Validates Groq JSON against the receipt extraction contract.
/// Does not invent missing values — null stays null.
abstract final class ReceiptExtractionValidator {
  static ExtractionParseResult parse(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      return ExtractionParseResult.malformed('Empty model response.');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(_extractJsonObject(trimmed));
    } catch (error) {
      return ExtractionParseResult.malformed(
        'Response was not valid JSON.',
        trimmed,
      );
    }

    if (decoded is! Map) {
      return ExtractionParseResult.schemaInvalid(
        'JSON root must be an object.',
        trimmed,
      );
    }

    final map = Map<String, Object?>.from(decoded);

    final amount = _readAmount(map['amount']);
    if (map.containsKey('amount') &&
        map['amount'] != null &&
        amount == null) {
      return ExtractionParseResult.schemaInvalid(
        'amount must be a non-negative number or null.',
        trimmed,
      );
    }

    final confidence = _readConfidenceMap(map['fieldConfidence']);
    if (map.containsKey('fieldConfidence') &&
        map['fieldConfidence'] != null &&
        confidence == null) {
      return ExtractionParseResult.schemaInvalid(
        'fieldConfidence must be an object of 0..1 numbers.',
        trimmed,
      );
    }

    final overall = _readUnitInterval(map['overallConfidence']);
    if (map.containsKey('overallConfidence') &&
        map['overallConfidence'] != null &&
        overall == null) {
      return ExtractionParseResult.schemaInvalid(
        'overallConfidence must be a number between 0 and 1, or null.',
        trimmed,
      );
    }

    final extraction = ReceiptExtraction(
      bankName: _readString(map['bankName']),
      senderBankAccountName: _readString(map['senderBankAccountName']),
      receiverBankAccountName: _readString(map['receiverBankAccountName']),
      amount: amount,
      currency: _readString(map['currency']),
      transactionReference: _readString(map['transactionReference']),
      transactionDateTimeRaw: _readString(
        map['transactionDateTime'] ?? map['transactionDateTimeRaw'],
      ),
      whatsappSender: _readString(map['whatsappSender']),
      adminMessage: _readString(map['adminMessage']),
      maskedAccountNumbers: _readStringList(map['maskedAccountNumbers']),
      uncertainFields: _readStringList(map['uncertainFields']),
      missingFields: _readStringList(map['missingFields']),
      fieldConfidence: confidence ?? const {},
      overallConfidence: overall,
      modelNotes: _readString(map['notes'] ?? map['modelNotes']),
    );

    return ExtractionParseResult.ok(extraction, trimmed);
  }

  static String _extractJsonObject(String raw) {
    if (raw.startsWith('{')) {
      return raw;
    }
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return raw.substring(start, end + 1);
    }
    return raw;
  }

  static String? _readString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'null' ||
        trimmed.toLowerCase() == 'unknown' ||
        trimmed.toLowerCase() == 'n/a') {
      return null;
    }
    return trimmed;
  }

  static double? _readAmount(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      final number = value.toDouble();
      return number < 0 ? null : number;
    }
    if (value is String) {
      final cleaned = value.replaceAll(',', '').replaceAll('Rs', '').trim();
      final parsed = double.tryParse(cleaned);
      if (parsed == null || parsed < 0) {
        return null;
      }
      return parsed;
    }
    return null;
  }

  static double? _readUnitInterval(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! num) {
      return null;
    }
    final number = value.toDouble();
    if (number < 0 || number > 1) {
      return null;
    }
    return number;
  }

  static Map<String, double>? _readConfidenceMap(Object? value) {
    if (value == null) {
      return {};
    }
    if (value is! Map) {
      return null;
    }
    final result = <String, double>{};
    for (final entry in value.entries) {
      final score = _readUnitInterval(entry.value);
      if (score == null) {
        return null;
      }
      result['${entry.key}'] = score;
    }
    return result;
  }

  static List<String> _readStringList(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
}
