import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/ai/ai_processing_mode.dart';
import 'package:ai_bank_receipt_manager/application/ai/ai_settings_service.dart';
import 'package:ai_bank_receipt_manager/application/ai/api_connection_tester.dart';
import 'package:ai_bank_receipt_manager/application/ai/api_test_result.dart';
import 'package:ai_bank_receipt_manager/application/ai/receipt_processing_coordinator.dart';
import 'package:ai_bank_receipt_manager/application/classification/business_classification_service.dart';
import 'package:ai_bank_receipt_manager/application/groq/groq_key_manager.dart';
import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/ocr/offline_ocr_engine.dart';
import 'package:ai_bank_receipt_manager/application/ocr/offline_receipt_extractor.dart';
import 'package:ai_bank_receipt_manager/data/ai/gemini_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/groq/secure_key_store.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/ai_extraction_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:ai_bank_receipt_manager/data/repositories/support_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_db_harness.dart';

void main() {
  group('AI processing mode persistence', () {
    test('mode persists across reopen', () async {
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final settings = AiSettingsService(
        AppSettingsRepository(harness.database),
      );
      await settings.setProcessingMode(AiProcessingMode.offlineOcr);
      await settings.setOfflineFallbackEnabled(true);
      expect(await settings.getProcessingMode(), AiProcessingMode.offlineOcr);

      await harness.reopen();
      final again = AiSettingsService(AppSettingsRepository(harness.database));
      expect(await again.getProcessingMode(), AiProcessingMode.offlineOcr);
      expect(await again.getOfflineFallbackEnabled(), isTrue);
    });
  });

  group('Exclusive provider routing', () {
    test('Offline OCR makes zero cloud requests', () async {
      var cloudCalls = 0;
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final settings = AiSettingsService(
        AppSettingsRepository(harness.database),
      );
      await settings.setProcessingMode(AiProcessingMode.offlineOcr);

      final groq = GroqVisionClient(
        httpClient: MockClient((request) async {
          cloudCalls++;
          return http.Response('{}', 500);
        }),
      );
      final gemini = GeminiVisionClient(
        httpClient: MockClient((request) async {
          cloudCalls++;
          return http.Response('{}', 500);
        }),
      );

      final coordinator = ReceiptProcessingCoordinator(
        settings: settings,
        configs: GroqApiConfigurationRepository(harness.database),
        keyStore: MemorySecureKeyStore(),
        extractions: AiExtractionRepository(harness.database),
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        ocrEngine: FakeOfflineOcrEngine(),
        groqClient: groq,
        geminiClient: gemini,
      );

      final image = File(harness.imagePath('ocr.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);
      final result = await coordinator.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isTrue);
      expect(cloudCalls, 0);
      expect(coordinator.lastCloudProviderCalled, isNull);
      expect(result.extraction!.receiverBankAccountName, contains('Azlan'));
    });

    test('Manual Entry does not call AI or OCR cloud', () async {
      var ocrCalls = 0;
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final settings = AiSettingsService(
        AppSettingsRepository(harness.database),
      );
      await settings.setProcessingMode(AiProcessingMode.manual);
      final coordinator = ReceiptProcessingCoordinator(
        settings: settings,
        configs: GroqApiConfigurationRepository(harness.database),
        keyStore: MemorySecureKeyStore(),
        extractions: AiExtractionRepository(harness.database),
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        ocrEngine: _CountingOcr(() => ocrCalls++),
      );
      final image = File(harness.imagePath('manual.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);
      final result = await coordinator.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isFalse);
      expect(ocrCalls, 0);
      expect(File(result.imagePath).existsSync(), isTrue);
    });

    test('Groq mode calls only Groq endpoint', () async {
      var groqCalls = 0;
      var geminiCalls = 0;
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final settings = AiSettingsService(
        AppSettingsRepository(harness.database),
      );
      await settings.setProcessingMode(AiProcessingMode.groq);
      final store = MemorySecureKeyStore();
      final configs = GroqApiConfigurationRepository(harness.database);
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: GroqVisionClient(
          httpClient: MockClient((request) async {
            groqCalls++;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'bankName': 'HBL',
                        'bankSenderName': 'Ali',
                        'bankReceiverName': 'Azlan Traders',
                        'amount': 1000,
                        'currency': 'PKR',
                      }),
                    },
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      await manager.addKey(
        label: 'G',
        apiKey: 'gsk_test_key_abcdefghijklmnop',
        setPreferred: true,
      );

      final coordinator = ReceiptProcessingCoordinator(
        settings: settings,
        configs: configs,
        keyStore: store,
        extractions: AiExtractionRepository(harness.database),
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        ocrEngine: FakeOfflineOcrEngine(),
        groqVision: ReceiptVisionService(
          keyManager: manager,
          configs: configs,
          extractions: AiExtractionRepository(harness.database),
          receipts: harness.receipts,
          imagesDirectoryPath: harness.paths.imagesDirectoryPath,
          client: GroqVisionClient(
            httpClient: MockClient((request) async {
              groqCalls++;
              return http.Response(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content': jsonEncode({
                          'bankName': 'HBL',
                          'amount': 1000,
                          'currency': 'PKR',
                        }),
                      },
                    },
                  ],
                }),
                200,
              );
            }),
          ),
        ),
        geminiClient: GeminiVisionClient(
          httpClient: MockClient((request) async {
            geminiCalls++;
            return http.Response('{}', 500);
          }),
        ),
      );

      final image = File(harness.imagePath('g.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final result = await coordinator.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isTrue);
      expect(groqCalls, greaterThan(0));
      expect(geminiCalls, 0);
      expect(coordinator.lastCloudProviderCalled, AiProviderKind.groq);
    });

    test('Groq failure falls back to OCR without calling Gemini', () async {
      var geminiCalls = 0;
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final settings = AiSettingsService(
        AppSettingsRepository(harness.database),
      );
      await settings.setProcessingMode(AiProcessingMode.groq);
      await settings.setOfflineFallbackEnabled(true);
      final store = MemorySecureKeyStore();
      final configs = GroqApiConfigurationRepository(harness.database);
      final manager = GroqKeyManager(
        configs: configs,
        keyStore: store,
        client: GroqVisionClient(
          httpClient: MockClient(
            (request) async => http.Response(
              '{"error":{"message":"Output tokens per minute (OTPM) Limit 1000"}}',
              429,
            ),
          ),
        ),
      );
      await manager.addKey(
        label: 'G',
        apiKey: 'gsk_test_key_abcdefghijklmnop',
        setPreferred: true,
      );

      final coordinator = ReceiptProcessingCoordinator(
        settings: settings,
        configs: configs,
        keyStore: store,
        extractions: AiExtractionRepository(harness.database),
        imagesDirectoryPath: harness.paths.imagesDirectoryPath,
        ocrEngine: FakeOfflineOcrEngine(),
        groqVision: ReceiptVisionService(
          keyManager: manager,
          configs: configs,
          extractions: AiExtractionRepository(harness.database),
          receipts: harness.receipts,
          imagesDirectoryPath: harness.paths.imagesDirectoryPath,
          client: GroqVisionClient(
            httpClient: MockClient(
              (request) async => http.Response(
                '{"error":{"message":"Output tokens per minute (OTPM) Limit 1000"}}',
                429,
              ),
            ),
          ),
        ),
        geminiClient: GeminiVisionClient(
          httpClient: MockClient((request) async {
            geminiCalls++;
            return http.Response('{}', 200);
          }),
        ),
      );

      final image = File(harness.imagePath('f.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final result = await coordinator.processAuthorizedImage(
        sourceFile: image,
        userAuthorizedUpload: true,
      );
      expect(result.isSuccess, isTrue);
      expect(geminiCalls, 0);
      expect(result.extraction!.adminMessage, contains('Rashid'));
    });
  });

  group('API tester', () {
    test(
      'invalid key yields Invalid API Key without using receipt images',
      () async {
        final harness = await TestDbHarness.create();
        addTearDown(harness.dispose);
        final store = MemorySecureKeyStore();
        final configs = GroqApiConfigurationRepository(harness.database);
        final manager = GroqKeyManager(
          configs: configs,
          keyStore: store,
          client: GroqVisionClient(
            httpClient: MockClient(
              (request) async => http.Response('{"error":"invalid"}', 401),
            ),
          ),
        );
        final created = await manager.addKey(
          label: 'Bad',
          apiKey: 'gsk_bad_key_xxxxxxxxxxxx',
        );
        final tester = ApiConnectionTester(
          configs: configs,
          keyStore: store,
          groqClient: GroqVisionClient(
            httpClient: MockClient(
              (request) async => http.Response('{"error":"invalid"}', 401),
            ),
          ),
        );
        final result = await tester.runConnectionTest(created.id);
        expect(result.status, ApiTestStatus.invalidApiKey);
        expect(result.explanation.toLowerCase(), isNot(contains('gsk_bad')));
        // Synthetic PNG only — never customer receipts.
        expect(ApiConnectionTester.syntheticPng.length, lessThan(200));
      },
    );

    test('rapid double test does not run concurrently', () async {
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final store = MemorySecureKeyStore();
      final configs = GroqApiConfigurationRepository(harness.database);
      var inflight = 0;
      var maxInflight = 0;
      final manager = GroqKeyManager(configs: configs, keyStore: store);
      final created = await manager.addKey(
        label: 'K',
        apiKey: 'gsk_test_key_abcdefghijklmnop',
      );
      final tester = ApiConnectionTester(
        configs: configs,
        keyStore: store,
        groqClient: GroqVisionClient(
          httpClient: MockClient((request) async {
            inflight++;
            if (inflight > maxInflight) {
              maxInflight = inflight;
            }
            await Future<void>.delayed(const Duration(milliseconds: 80));
            inflight--;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{"ok":true}'},
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      final futures = [
        tester.runConnectionTest(created.id),
        tester.runConnectionTest(created.id),
      ];
      final results = await Future.wait(futures);
      expect(maxInflight, lessThanOrEqualTo(1));
      expect(
        results.any((r) => r.status == ApiTestStatus.testNotCompleted) ||
            results.every((r) => r.status == ApiTestStatus.working),
        isTrue,
      );
    });
  });

  group('Offline extraction + office matching', () {
    test(
      'OCR text maps Azlan Traders to Mutalib and Rashid customer',
      () async {
        final harness = await TestDbHarness.create();
        addTearDown(harness.dispose);
        final extraction = OfflineReceiptExtractor().extract(
          const OfflineOcrResult(
            fullText:
                'HBL\nFrom: Bright Traders Company\nTo: Azlan Traders\n'
                'Amount: Rs 1,799,200\nYe Rashid ke paise hain',
          ),
        );
        expect(extraction.amount, 1799200);
        expect(extraction.receiverBankAccountName, contains('Azlan'));
        expect(extraction.suggestedCustomerName, 'Rashid');

        final offices = OfficeAccountRepository(harness.database);
        final customers = CustomerRepository(harness.database);
        final rashid = await customers.create(name: 'Rashid');
        await customers.addAlias(
          customerId: rashid.id,
          aliasName: 'Rashid',
          approvalStatus: AliasApprovalStatus.approved,
        );
        final accounts = await offices.listSelectableForNewEntries();
        final aliases = <String, List<OfficeAccountAliasRecord>>{};
        for (final a in accounts) {
          aliases[a.id] = await offices.listAliases(a.id);
        }
        final classified = BusinessClassificationService().classify(
          input: ClassificationInput(
            bankSenderName: extraction.senderBankAccountName,
            bankReceiverName: extraction.receiverBankAccountName,
            adminMessage: extraction.adminMessage,
            whatsappSender: 'Mujtaba',
          ),
          accounts: accounts,
          accountAliases: aliases,
          customers: [rashid],
          customerAliases: {rashid.id: await customers.listAliases(rashid.id)},
          dealers: const [],
          dealerAliases: const {},
        );
        expect(classified.officeAccountId, DefaultOfficeAccountIds.mutalib);
        expect(classified.customerId, rashid.id);
        expect(classified.proposedReceiptType, DbReceiptType.received);
      },
    );

    test('schema migrates to v7 without wiping receipts', () async {
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      await harness.receipts.appendImport(
        accountingDate: DateTime(2026, 10, 11),
        source: 'v7',
        drafts: [harness.draft(transactionId: 'KEEP', amount: 500)],
      );
      await harness.reopen();
      final rows = await harness.receipts.listByAccountingDate(
        DateTime(2026, 10, 11),
      );
      expect(rows, hasLength(1));
      final configs = GroqApiConfigurationRepository(harness.database);
      final created = await configs.create(
        label: 'Gemini',
        endpoint: 'https://generativelanguage.googleapis.com/v1beta',
        providerKind: AiProviderKind.gemini,
      );
      expect(created.providerKind, AiProviderKind.gemini);
    });
  });
}

class _CountingOcr implements OfflineOcrEngine {
  _CountingOcr(this.onCall);
  final void Function() onCall;

  @override
  Future<OfflineOcrResult> recognize(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    onCall();
    return const OfflineOcrResult(fullText: '');
  }
}
