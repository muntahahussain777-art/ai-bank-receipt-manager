import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/groq/groq_key_manager.dart';
import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/receipt_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_db_harness.dart';

void main() {
  group('ReceiptExtractionValidator', () {
    test('1 clear receipt JSON parses all fields', () {
      final result = ReceiptExtractionValidator.parse(jsonEncode({
        'bankName': 'Meezan Bank',
        'senderBankAccountName': 'Ali Ahmed',
        'receiverBankAccountName': 'Azlan Traders',
        'amount': 125000.5,
        'currency': 'PKR',
        'transactionReference': 'TXN-991',
        'transactionDateTime': '2026-10-10T14:22:00',
        'whatsappSender': 'Office Admin',
        'adminMessage': 'Customer Ali Ahmed Mutalib',
        'maskedAccountNumbers': ['****1234'],
        'uncertainFields': <String>[],
        'missingFields': <String>[],
        'fieldConfidence': {'amount': 0.95, 'bankName': 0.9},
        'overallConfidence': 0.92,
      }));
      expect(result.isOk, isTrue);
      expect(result.extraction!.bankName, 'Meezan Bank');
      expect(result.extraction!.amount, 125000.5);
      expect(result.extraction!.transactionReference, 'TXN-991');
      expect(result.extraction!.adminMessage, contains('Ali Ahmed'));
    });

    test('2 blurry receipt leaves amount null without inventing', () {
      final result = ReceiptExtractionValidator.parse(jsonEncode({
        'bankName': 'HBL',
        'amount': null,
        'currency': 'PKR',
        'missingFields': ['amount', 'transactionReference'],
        'uncertainFields': ['senderBankAccountName'],
        'overallConfidence': 0.2,
      }));
      expect(result.isOk, isTrue);
      expect(result.extraction!.amount, isNull);
      expect(result.extraction!.transactionReference, isNull);
      expect(result.extraction!.missingFields, contains('amount'));
    });

    test('3 missing transaction reference stays null', () {
      final result = ReceiptExtractionValidator.parse(jsonEncode({
        'bankName': 'UBL',
        'amount': 500,
        'transactionReference': null,
        'missingFields': ['transactionReference'],
      }));
      expect(result.extraction!.transactionReference, isNull);
    });

    test('4 screenshot with admin note keeps whatsapp fields', () {
      final result = ReceiptExtractionValidator.parse(jsonEncode({
        'bankName': 'JazzCash',
        'amount': 2000,
        'whatsappSender': '+92 300 1112222',
        'adminMessage': 'Dealer Farhan AD outgoing',
      }));
      expect(result.extraction!.whatsappSender, startsWith('+92'));
      expect(result.extraction!.adminMessage, contains('Farhan'));
    });

    test('5 incorrect AI JSON is malformed', () {
      final result = ReceiptExtractionValidator.parse('not-json {{{');
      expect(result.status, ExtractionParseStatus.malformed);
    });

    test('5b schema invalid amount rejected', () {
      final result = ReceiptExtractionValidator.parse(
        jsonEncode({'amount': 'not-a-number', 'bankName': 'HBL'}),
      );
      expect(result.status, ExtractionParseStatus.schemaInvalid);
    });

    test('unknown / n/a strings become null (no invention)', () {
      final result = ReceiptExtractionValidator.parse(jsonEncode({
        'bankName': 'unknown',
        'currency': 'N/A',
        'transactionReference': 'null',
      }));
      expect(result.extraction!.bankName, isNull);
      expect(result.extraction!.currency, isNull);
      expect(result.extraction!.transactionReference, isNull);
    });
  });

  group('sanitize + mask', () {
    test('never exposes full keys in sanitized messages', () {
      final sanitized = sanitizeProviderMessage(
        'Unauthorized Bearer gsk_live_ABCDEFG123456 and api_key=secret99',
      );
      expect(sanitized.contains('gsk_live_ABCDEFG123456'), isFalse);
      expect(sanitized.contains('Bearer ***'), isTrue);
    });

    test('maskApiKey hides middle', () {
      expect(maskApiKey('gsk_abcdefghijklmnop'), 'gsk_…mnop');
    });
  });

  group('Groq client + key fallback', () {
    late TestDbHarness harness;
    late MemorySecureKeyStore store;
    late GroqApiConfigurationRepository configs;
    late GroqKeyManager keyManager;
    late AiExtractionRepository extractions;
    late ReceiptRepository receipts;

    setUp(() async {
      harness = await TestDbHarness.create();
      store = MemorySecureKeyStore();
      configs = GroqApiConfigurationRepository(harness.database);
      keyManager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: GroqVisionClient(
          httpClient: MockClient((request) async {
            return http.Response('{"choices":[{"message":{"content":"{\\"ok\\":true}"}}]}', 200);
          }),
        ),
      );
      extractions = AiExtractionRepository(harness.database);
      receipts = ReceiptRepository(harness.database);
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('6 invalid API key records authentication error', () async {
      final badClient = GroqVisionClient(
        httpClient: MockClient((request) async {
          return http.Response('{"error":{"message":"Invalid API Key"}}', 401);
        }),
      );
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: badClient,
      );
      final config = await manager.addKey(
        label: 'Bad',
        apiKey: 'gsk_bad_key_value_xxxx',
        setPreferred: true,
      );
      await expectLater(
        manager.testKey(config.id),
        throwsA(
          isA<GroqFailure>().having(
            (f) => f.kind,
            'kind',
            GroqFailureKind.authentication,
          ),
        ),
      );
      final stored = await configs.getById(config.id);
      expect(stored!.lastErrorStatus, 'authentication');
      expect(stored.maskedKeyHint, isNot(contains('gsk_bad_key_value_xxxx')));
    });

    test('7 rate limit falls back to next enabled key', () async {
      var calls = 0;
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response('{"error":"rate limited"}', 429);
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'bankName': 'Alfalah',
                      'amount': 900,
                      'currency': 'PKR',
                      'missingFields': <String>[],
                    }),
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: client,
      );
      await manager.addKey(
        label: 'First',
        apiKey: 'gsk_first_key_aaaaaaaa',
        setPreferred: true,
      );
      await manager.addKey(
        label: 'Second',
        apiKey: 'gsk_second_key_bbbbbbbb',
        setPreferred: false,
      );

      final vision = ReceiptVisionService(
        keyManager: manager,
        configs: configs,
        extractions: extractions,
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        client: client,
      );

      final image = await _writeTempImage(harness);
      final result = await vision.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isTrue);
      expect(result.extraction!.bankName, 'Alfalah');
      expect(calls, 2);
    });

    test('8 no internet marks failed and preserves image', () async {
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          throw const SocketException('Failed host lookup');
        }),
      );
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: client,
      );
      await manager.addKey(label: 'Only', apiKey: 'gsk_only_key_cccccccc');

      final vision = ReceiptVisionService(
        keyManager: manager,
        configs: configs,
        extractions: extractions,
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        client: client,
      );

      final image = await _writeTempImage(harness);
      final result = await vision.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure!.kind, GroqFailureKind.network);
      expect(File(result.imagePath).existsSync(), isTrue);
      expect(
        result.extractionRecord.processingStatus,
        AiProcessingStatus.failed,
      );
    });

    test('9 multiple enabled keys prefer preferred then others', () async {
      await keyManager.addKey(
        label: 'B',
        apiKey: 'gsk_bbbbbbbbbbbbbbbb',
        setPreferred: false,
      );
      await keyManager.addKey(
        label: 'A Preferred',
        apiKey: 'gsk_aaaaaaaaaaaaaaaa',
        setPreferred: true,
      );
      await keyManager.setEnabled(
        id: (await configs.listActive()).firstWhere((c) => c.label == 'B').id,
        enabled: false,
      );
      final enabled = await configs.listEnabledForFallback();
      expect(enabled, hasLength(1));
      expect(enabled.first.label, 'A Preferred');
      expect(enabled.first.isActive, isTrue);
    });

    test('10 user correction saved separately from raw AI', () async {
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'bankName': 'MCB',
                      'amount': 100,
                      'currency': 'PKR',
                      'transactionReference': 'WRONG',
                    }),
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: client,
      );
      await manager.addKey(label: 'K', apiKey: 'gsk_correct_key_dddddddd');
      final vision = ReceiptVisionService(
        keyManager: manager,
        configs: configs,
        extractions: extractions,
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        client: client,
      );
      final image = await _writeTempImage(harness);
      final job = await vision.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      final corrected = ReceiptExtraction(
        bankName: 'MCB',
        amount: 100,
        currency: 'PKR',
        transactionReference: 'FIXED-REF',
      );
      final saved = await vision.saveCorrectedImport(
        extractionRecord: job.extractionRecord,
        corrected: corrected,
        accountingDate: DateTime(2026, 10, 10),
      );
      expect(saved.transactionId, 'FIXED-REF');
      final ai = await extractions.getById(job.extractionRecord.id);
      expect(ai!.rawAiJson, contains('WRONG'));
      expect(ai.userCorrectedJson, contains('FIXED-REF'));
      expect(ai.appliedToReceipt, isTrue);
      expect(ai.rawAiJson == ai.userCorrectedJson, isFalse);
    });

    test('11 previously entered receipt reprocess is proposal only', () async {
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'bankName': 'HBL',
                      'amount': 99999,
                      'currency': 'PKR',
                      'transactionReference': 'NEW-AI-REF',
                    }),
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: client,
      );
      await manager.addKey(label: 'K', apiKey: 'gsk_reprocess_key_eeeeeeee');
      final vision = ReceiptVisionService(
        keyManager: manager,
        configs: configs,
        extractions: extractions,
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        client: client,
      );

      final image = await _writeTempImage(harness);
      final batch = await receipts.appendImport(
        accountingDate: DateTime(2026, 10, 10),
        source: 'seed',
        drafts: [
          ReceiptImportDraft(
            id: 'entered-1',
            bankName: 'HBL',
            amount: 1500,
            currency: 'PKR',
            transactionId: 'ORIGINAL-REF',
            originalImagePath: image.path,
            imageHash: 'abc',
          ),
        ],
      );
      expect(batch.receiptCount, 1);
      await receipts.markEntered(id: 'entered-1', enteredBy: 'tester');

      final before = await receipts.getById('entered-1');
      expect(before!.entryStatus, DbEntryStatus.entered);
      expect(before.amount, 1500);

      final result = await vision.reprocessEnteredReceipt(
        receiptId: 'entered-1',
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isTrue);
      expect(
        result.extractionRecord.processingStatus,
        AiProcessingStatus.proposed,
      );
      expect(result.extractionRecord.proposedJson, contains('NEW-AI-REF'));
      expect(result.extractionRecord.appliedToReceipt, isFalse);

      final after = await receipts.getById('entered-1');
      expect(after!.entryStatus, DbEntryStatus.entered);
      expect(after.amount, 1500);
      expect(after.transactionId, 'ORIGINAL-REF');
      expect(after.bankName, 'HBL');
      expect(after.reviewStatus, DbReviewStatus.pendingReview);
    });

    test('unauthorized upload refused', () async {
      final vision = ReceiptVisionService(
        keyManager: keyManager,
        configs: configs,
        extractions: extractions,
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
      );
      final image = await _writeTempImage(harness);
      await expectLater(
        vision.processAuthorizedImage(
          sourceFile: image,
          userAuthorizedUpload: false,
        ),
        throwsA(
          isA<GroqFailure>().having(
            (f) => f.kind,
            'kind',
            GroqFailureKind.unauthorizedUpload,
          ),
        ),
      );
    });

    test('keys never stored in SQLite plaintext', () async {
      await keyManager.addKey(
        label: 'Secure',
        apiKey: 'gsk_super_secret_value_ffff',
      );
      final db = await harness.database.database;
      final rows = await db.query('groq_api_configurations');
      final blob = jsonEncode(rows);
      expect(blob.contains('gsk_super_secret_value_ffff'), isFalse);
      expect(rows.first['secure_key_slot'], isNotNull);
      expect(rows.first['masked_key_hint'], isNot(contains('super_secret')));
    });

    test('malformed provider content becomes failed job with image kept', () async {
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'TOTALLY NOT JSON'},
                },
              ],
            }),
            200,
          );
        }),
      );
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: client,
      );
      await manager.addKey(label: 'K', apiKey: 'gsk_malformed_key_gggggggg');
      final vision = ReceiptVisionService(
        keyManager: manager,
        configs: configs,
        extractions: extractions,
        receipts: receipts,
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        client: client,
      );
      final image = await _writeTempImage(harness);
      final result = await vision.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure!.kind, GroqFailureKind.malformedResponse);
      expect(File(result.imagePath).existsSync(), isTrue);
    });

    test('model unavailable is classified', () async {
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error":{"message":"The model `old-model` does not exist"}}',
            400,
          );
        }),
      );
      await expectLater(
        client.extractReceipt(
          apiKey: 'gsk_x',
          endpoint: GroqConstants.defaultEndpoint,
          model: 'old-model',
          imageBytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/jpeg',
        ),
        throwsA(
          isA<GroqFailure>().having(
            (f) => f.kind,
            'kind',
            GroqFailureKind.modelUnavailable,
          ),
        ),
      );
    });

    test('timeout is retryable with next key', () async {
      final client = GroqVisionClient(
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        client.testKey(
          apiKey: 'gsk_x',
          endpoint: GroqConstants.defaultEndpoint,
          model: GroqConstants.defaultVisionModel,
        ),
        throwsA(
          isA<GroqFailure>()
              .having((f) => f.kind, 'kind', GroqFailureKind.timeout)
              .having((f) => f.retryableWithNextKey, 'retryable', isTrue),
        ),
      );
    });
  });
}

Future<File> _writeTempImage(TestDbHarness harness) async {
  final file = File('${harness.paths.imagesDirectoryPath}/sample.jpg');
  await file.writeAsBytes(List<int>.generate(64, (i) => i));
  return file;
}
