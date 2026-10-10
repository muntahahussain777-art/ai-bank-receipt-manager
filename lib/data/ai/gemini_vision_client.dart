import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/data/ai/gemini_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:http/http.dart' as http;

/// Google Gemini Generative Language API (vision + JSON).
class GeminiVisionClient {
  GeminiVisionClient({
    http.Client? httpClient,
    this.timeout = GeminiConstants.requestTimeout,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  Future<void> testConnection({
    required String apiKey,
    required String endpoint,
    required String model,
  }) async {
    final uri = _generateUri(endpoint, model, apiKey);
    final response = await _send(
      uri: uri,
      body: {
        'contents': [
          {
            'parts': [
              {'text': 'Reply with JSON object {"ok":true} only.'},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0,
          'maxOutputTokens': 32,
          'responseMimeType': 'application/json',
        },
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GroqFailure.fromHttpStatus(
        response.statusCode,
        response.body,
        headers: response.headers,
      );
    }
  }

  Future<ExtractionParseResult> extractReceipt({
    required String apiKey,
    required String endpoint,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    String? configId,
    int? maxOutputTokens,
  }) async {
    final uri = _generateUri(endpoint, model, apiKey);
    final response = await _send(
      uri: uri,
      body: {
        'contents': [
          {
            'parts': [
              {'text': GroqConstants.extractionSystemPrompt},
              {'text': GroqConstants.extractionUserPrompt},
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Encode(imageBytes),
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0,
          'maxOutputTokens':
              maxOutputTokens ?? GeminiConstants.defaultMaxOutputTokens,
          'responseMimeType': 'application/json',
        },
      },
      configId: configId,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GroqFailure.fromHttpStatus(
        response.statusCode,
        response.body,
        configId: configId,
        headers: response.headers,
      );
    }
    final content = _readText(response.body);
    final parsed = ReceiptExtractionValidator.parse(content);
    if (!parsed.isOk) {
      throw GroqFailure(
        kind: parsed.status == ExtractionParseStatus.malformed
            ? GroqFailureKind.malformedResponse
            : GroqFailureKind.schemaInvalid,
        message: parsed.errorMessage ?? 'Invalid Gemini extraction JSON.',
        configId: configId,
      );
    }
    return parsed;
  }

  Future<http.Response> _send({
    required Uri uri,
    required Map<String, Object?> body,
    String? configId,
  }) async {
    try {
      return await _http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw GroqFailure(
        kind: GroqFailureKind.timeout,
        message: 'Gemini request timed out after ${timeout.inSeconds}s.',
        retryableWithNextKey: true,
        configId: configId,
      );
    } catch (error) {
      throw GroqFailure(
        kind: GroqFailureKind.network,
        message: sanitizeProviderMessage('$error'),
        retryableWithNextKey: true,
        configId: configId,
      );
    }
  }

  Uri _generateUri(String endpoint, String model, String apiKey) {
    final base = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    return Uri.parse(
      '$base/models/$model:generateContent',
    ).replace(queryParameters: {'key': apiKey});
  }

  String _readText(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Gemini response was not an object.',
      );
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Gemini response missing candidates.',
      );
    }
    final first = candidates.first;
    if (first is! Map) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Gemini candidate invalid.',
      );
    }
    final content = first['content'];
    if (content is! Map) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Gemini content missing.',
      );
    }
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Gemini parts missing.',
      );
    }
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] is String) {
        buffer.write(part['text']);
      }
    }
    final text = buffer.toString();
    if (text.isEmpty) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Gemini returned empty text.',
      );
    }
    return text;
  }

  void close() => _http.close();
}
