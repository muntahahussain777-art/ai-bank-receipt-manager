import 'package:ai_bank_receipt_manager/application/classification/admin_note_parser.dart';
import 'package:ai_bank_receipt_manager/application/ocr/offline_ocr_engine.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';

/// Rule-based local extraction from OCR text. Never invents missing values.
class OfflineReceiptExtractor {
  ReceiptExtraction extract(OfflineOcrResult ocr) {
    final text = ocr.fullText;
    final lines = ocr.lines.map((l) => l.text).toList();
    if (text.trim().isEmpty && lines.isEmpty) {
      return const ReceiptExtraction(
        currency: 'PKR',
        missingFields: [
          'bankName',
          'amount',
          'transactionReference',
          'senderBankAccountName',
          'receiverBankAccountName',
        ],
        overallConfidence: 0,
        modelNotes: 'Offline OCR returned no readable text.',
      );
    }

    final joined = lines.isEmpty ? text : lines.join('\n');
    final amount = _extractAmount(joined);
    final bank = _extractBank(joined);
    final sender = _extractLabeled(joined, const [
      'from',
      'sender',
      'paid by',
      'debit',
      'sent by',
    ]);
    final receiver = _extractLabeled(joined, const [
      'to',
      'receiver',
      'credited to',
      'credit',
      'received by',
      'beneficiary',
    ]);
    final reference = _extractReference(joined);
    final dateRaw = _extractDate(joined);
    final admin = _extractAdminNote(joined);
    final attributions = AdminNoteParser.extractAttributionNames(admin);
    final uncertain = <String>[];
    final missing = <String>[];
    if (amount == null) {
      missing.add('amount');
    }
    if (bank == null) {
      missing.add('bankName');
    }
    if (sender == null) {
      missing.add('senderBankAccountName');
    }
    if (receiver == null) {
      missing.add('receiverBankAccountName');
    }
    if (reference == null) {
      missing.add('transactionReference');
    }
    if (amount != null && amount < 1) {
      uncertain.add('amount');
    }

    var confidence = 0.35;
    if (amount != null) {
      confidence += 0.2;
    }
    if (bank != null) {
      confidence += 0.1;
    }
    if (sender != null && receiver != null) {
      confidence += 0.15;
    }
    if (reference != null) {
      confidence += 0.1;
    }
    if (admin != null) {
      confidence += 0.05;
    }

    return ReceiptExtraction(
      bankName: bank,
      senderBankAccountName: sender,
      receiverBankAccountName: receiver,
      amount: amount,
      currency: amount == null ? 'PKR' : _detectCurrency(joined),
      transactionReference: reference,
      transactionDateTimeRaw: dateRaw,
      adminMessage: admin,
      suggestedCustomerName: attributions.isEmpty ? null : attributions.first,
      suggestedDealerName: AdminNoteParser.suggestsDealer(admin)
          ? (attributions.isEmpty ? null : attributions.first)
          : null,
      maskedAccountNumbers: _maskedAccounts(joined),
      uncertainFields: uncertain,
      missingFields: missing,
      overallConfidence: confidence.clamp(0.0, 0.95),
      modelNotes: 'Extracted via ${ocr.engineName}. Confirm before saving.',
      fieldConfidence: {
        if (amount != null) 'amount': amount >= 1 ? 0.7 : 0.4,
        if (bank != null) 'bankName': 0.65,
        if (sender != null) 'senderBankAccountName': 0.55,
        if (receiver != null) 'receiverBankAccountName': 0.55,
      },
    );
  }

  double? _extractAmount(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'(?:rs\.?|pkr|amount|total|tid amount)\s*[:\-]?\s*([\d,]+\.?\d*)',
        caseSensitive: false,
      ),
      RegExp(r'([\d,]{3,}\.\d{2})\b'),
      RegExp(r'\b([\d,]{4,})\b'),
    ];
    final candidates = <double>[];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final raw = match.group(1)?.replaceAll(',', '');
        final value = double.tryParse(raw ?? '');
        if (value != null && value >= 10 && value <= 500000000) {
          // Skip likely account numbers / years.
          if (value >= 1900 &&
              value <= 2100 &&
              value == value.roundToDouble()) {
            continue;
          }
          candidates.add(value);
        }
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort();
    // Prefer the largest plausible transfer amount (avoid fees).
    return candidates.last;
  }

  String? _extractBank(String text) {
    const banks = [
      'Meezan',
      'HBL',
      'UBL',
      'MCB',
      'Alfalah',
      'Allied Bank',
      'Bank Al Habib',
      'JazzCash',
      'Easypaisa',
      'EasyPaisa',
      'Habib Metro',
      'Faysal',
      'Askari',
      'Standard Chartered',
      'Samba',
    ];
    final lower = text.toLowerCase();
    for (final bank in banks) {
      if (lower.contains(bank.toLowerCase())) {
        return bank;
      }
    }
    return null;
  }

  String? _extractLabeled(String text, List<String> labels) {
    for (final label in labels) {
      final pattern = RegExp(
        '$label\\s*[:\\-]?\\s*([A-Za-z\\u0600-\\u06FF][A-Za-z\\u0600-\\u06FF0-9 .,&\\-]{1,48})',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.length >= 2) {
        return value.replaceAll(RegExp(r'\s+'), ' ');
      }
    }
    return null;
  }

  String? _extractReference(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'(?:tid|txn|transaction(?:\s*id)?|reference|ref\.?|rrn)\s*[:\-]?\s*([A-Za-z0-9\-]{6,})',
        caseSensitive: false,
      ),
      RegExp(r'\b([A-Z]{2,5}[-_]?\d{6,})\b'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  String? _extractDate(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)',
      ),
      RegExp(
        r'\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4})',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  String? _extractAdminNote(String text) {
    final lower = text.toLowerCase();
    final markers = [
      'ke paise',
      'ke paas',
      'nill',
      'nil',
      'dealer',
      'ka payment',
      'ye ',
    ];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.length < 4) {
        continue;
      }
      final lineLower = trimmed.toLowerCase();
      if (markers.any(lineLower.contains)) {
        return trimmed;
      }
    }
    if (markers.any(lower.contains)) {
      // Last non-empty line often holds the WhatsApp caption.
      final lines = [
        for (final line in text.split(RegExp(r'[\r\n]+')))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      if (lines.isNotEmpty) {
        return lines.last;
      }
    }
    return null;
  }

  String _detectCurrency(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('usd') || lower.contains('\$')) {
      return 'USD';
    }
    return 'PKR';
  }

  List<String> _maskedAccounts(String text) {
    final matches = RegExp(
      r'\*{2,}\d{3,4}|\d{2,4}\*{2,}\d{2,4}',
    ).allMatches(text);
    return [for (final m in matches) m.group(0)!].take(4).toList();
  }
}
