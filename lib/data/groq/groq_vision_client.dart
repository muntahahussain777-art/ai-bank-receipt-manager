import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:http/http.dart' as http;

class GroqVisionClient {
  GroqVisionClient({
    http.Client? httpClient,
    this.timeout = GroqConstants.requestTimeout,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  /// Lightweight auth / model check without uploading a receipt image.
  Future<void> testKey({
    required String apiKey,
    required String endpoint,
    required String model,
  }) async {
    final uri = Uri.parse(
      '${_trimSlash(endpoint)}${GroqConstants.chatCompletionsPath}',
    );
    final response = await _send(
      uri: uri,
      apiKey: apiKey,
      body: {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content':
                'Reply with a JSON object containing a single boolean field '
                'ok set to true.',
          },
        ],
        'temperature': 0,
        'max_completion_tokens': 64,
        'response_format': {'type': 'json_object'},
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GroqFailure.fromHttpStatus(response.statusCode, response.body);
    }
  }

  Future<ExtractionParseResult> extractReceipt({
    required String apiKey,
    required String endpoint,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    String? configId,
  }) async {
    if (imageBytes.lengthInBytes > GroqConstants.maxImageBytes) {
      throw const GroqFailure(
        kind: GroqFailureKind.imageTooLarge,
        message: 'Image exceeds the 20MB Groq Vision limit.',
      );
    }

    final uri = Uri.parse(
      '${_trimSlash(endpoint)}${GroqConstants.chatCompletionsPath}',
    );
    final dataUrl = 'data:$mimeType;base64,${base64Encode(imageBytes)}';

    final response = await _send(
      uri: uri,
      apiKey: apiKey,
      body: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': GroqConstants.extractionSystemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': GroqConstants.extractionUserPrompt},
              {
                'type': 'image_url',
                'image_url': {'url': dataUrl},
              },
            ],
          },
        ],
        'temperature': 0,
        'max_completion_tokens': 2048,
        'response_format': {'type': 'json_object'},
      },
      configId: configId,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GroqFailure.fromHttpStatus(
        response.statusCode,
        response.body,
        configId: configId,
      );
    }

    final content = _readMessageContent(response.body);
    final parsed = ReceiptExtractionValidator.parse(content);
    if (!parsed.isOk) {
      throw GroqFailure(
        kind: parsed.status == ExtractionParseStatus.malformed
            ? GroqFailureKind.malformedResponse
            : GroqFailureKind.schemaInvalid,
        message: parsed.errorMessage ?? 'Invalid extraction JSON.',
        configId: configId,
        retryableWithNextKey: false,
      );
    }
    return parsed;
  }

  Future<http.Response> _send({
    required Uri uri,
    required String apiKey,
    required Map<String, Object?> body,
    String? configId,
  }) async {
    try {
      return await _http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw GroqFailure(
        kind: GroqFailureKind.timeout,
        message: 'Groq request timed out after ${timeout.inSeconds}s.',
        retryableWithNextKey: true,
        configId: configId,
      );
    } on http.ClientException catch (error) {
      throw GroqFailure(
        kind: GroqFailureKind.network,
        message: sanitizeProviderMessage(error.message),
        retryableWithNextKey: true,
        configId: configId,
      );
    } on SocketException catch (error) {
      throw GroqFailure(
        kind: GroqFailureKind.network,
        message: sanitizeProviderMessage(error.message),
        retryableWithNextKey: true,
        configId: configId,
      );
    } catch (error) {
      final text = '$error';
      if (text.toLowerCase().contains('socket') ||
          text.toLowerCase().contains('failed host lookup') ||
          text.toLowerCase().contains('network')) {
        throw GroqFailure(
          kind: GroqFailureKind.network,
          message: sanitizeProviderMessage(text),
          retryableWithNextKey: true,
          configId: configId,
        );
      }
      rethrow;
    }
  }

  String _readMessageContent(String body) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Provider response was not JSON.',
      );
    }
    if (decoded is! Map) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Provider response root was not an object.',
      );
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Provider response missing choices.',
      );
    }
    final first = choices.first;
    if (first is! Map) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Provider choice was not an object.',
      );
    }
    final message = first['message'];
    if (message is! Map) {
      throw const GroqFailure(
        kind: GroqFailureKind.malformedResponse,
        message: 'Provider message was missing.',
      );
    }
    final content = message['content'];
    if (content is String) {
      return content;
    }
    throw const GroqFailure(
      kind: GroqFailureKind.malformedResponse,
      message: 'Provider message content was not a string.',
    );
  }

  static String _trimSlash(String endpoint) {
    if (endpoint.endsWith('/')) {
      return endpoint.substring(0, endpoint.length - 1);
    }
    return endpoint;
  }

  void close() => _http.close();
}
