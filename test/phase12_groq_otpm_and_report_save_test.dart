import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_bank_receipt_manager/application/classification/admin_note_parser.dart';
import 'package:ai_bank_receipt_manager/application/classification/business_classification_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/gallery_image_saver.dart';
import 'package:ai_bank_receipt_manager/application/reports/pdf_page_rasterizer.dart';
import 'package:ai_bank_receipt_manager/application/reports/pdf_report_builder.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_query_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_save_service.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_constants.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_vision_client.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/repositories/office_account_repository.dart';
import 'package:ai_bank_receipt_manager/data/repositories/party_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_db_harness.dart';

void main() {
  group('Groq OTPM / token budget', () {
    test('qwen profile stays under 1000 OTPM headroom', () {
      final profile = GroqConstants.profileForModel('qwen/qwen3.8-27b');
      expect(profile.maxCompletionTokens, lessThanOrEqualTo(750));
      expect(profile.maxCompletionTokens, greaterThanOrEqualTo(600));
      expect(profile.reasoningEffort, 'none');
    });

    test('extractReceipt requests compact max_completion_tokens', () async {
      Map<String, dynamic>? body;
      final client = GroqVisionClient(
        httpClient: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'bankName': 'HBL',
                      'bankSenderName': 'Bright Traders Company',
                      'bankReceiverName': 'Azlan Traders',
                      'amount': 1799200,
                      'currency': 'PKR',
                      'adminMessage': 'Ye Rashid ke paise hain',
                      'suggestedCustomerName': 'Rashid',
                      'overallConfidence': 0.9,
                    }),
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      await client.extractReceipt(
        apiKey: 'gsk_test',
        endpoint: GroqConstants.defaultEndpoint,
        model: GroqConstants.defaultVisionModel,
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        mimeType: 'image/jpeg',
      );

      expect(body, isNotNull);
      final tokens = body!['max_completion_tokens'] as int;
      expect(tokens, lessThanOrEqualTo(750));
      expect(tokens, isNot(equals(1921)));
      expect(tokens, isNot(equals(2048)));
      expect(body!['reasoning_effort'], 'none');
      expect(body!['response_format'], {'type': 'json_object'});
    });

    test('OTPM error is not key-rotated and uses friendly message', () {
      final failure = GroqFailure.fromHttpStatus(
        429,
        jsonEncode({
          'error': {
            'message':
                'Output tokens per minute (OTPM) Limit 1000, Requested 1921',
            'type': 'tokens',
            'code': 'rate_limit_exceeded',
          },
        }),
      );
      expect(failure.kind, GroqFailureKind.outputTokenLimit);
      expect(failure.retryableWithNextKey, isFalse);
      expect(
        failure.userFacingMessage,
        contains('AI processing is temporarily unavailable'),
      );
      expect(failure.userFacingMessage.toLowerCase(), isNot(contains('otpm')));
      expect(failure.userFacingMessage.toLowerCase(), isNot(contains('org_')));
    });

    test('ordinary 429 remains retryable rateLimit', () {
      final failure = GroqFailure.fromHttpStatus(
        429,
        '{"error":{"message":"Rate limit reached for requests"}}',
        headers: {'retry-after': '2'},
      );
      expect(failure.kind, GroqFailureKind.rateLimit);
      expect(failure.retryableWithNextKey, isTrue);
      expect(failure.retryAfter, const Duration(seconds: 2));
    });
  });

  group('Office + WhatsApp attribution', () {
    test(
      'Bright Traders → Azlan Traders with Rashid note matches Mutalib',
      () async {
        final harness = await TestDbHarness.create();
        addTearDown(harness.dispose);
        final offices = OfficeAccountRepository(harness.database);
        final customers = CustomerRepository(harness.database);
        final accounts = await offices.listSelectableForNewEntries();
        final aliases = <String, List<OfficeAccountAliasRecord>>{};
        for (final a in accounts) {
          aliases[a.id] = await offices.listAliases(a.id);
        }
        final rashid = await customers.create(name: 'Rashid');
        await customers.addAlias(
          customerId: rashid.id,
          aliasName: 'Rashid',
          approvalStatus: AliasApprovalStatus.approved,
        );

        final classified = BusinessClassificationService().classify(
          input: const ClassificationInput(
            bankSenderName: 'Bright Traders Company',
            bankReceiverName: 'Azlan Traders',
            adminMessage: 'Ye Rashid ke paise hain',
            whatsappSender: 'Mujtaba',
            bankDirectionHint: DbReceiptType.received,
          ),
          accounts: accounts,
          accountAliases: aliases,
          customers: [rashid],
          customerAliases: {rashid.id: await customers.listAliases(rashid.id)},
          dealers: const [],
          dealerAliases: const {},
        );

        expect(classified.officeAccountId, DefaultOfficeAccountIds.mutalib);
        expect(classified.proposedReceiptType, DbReceiptType.received);
        expect(classified.customerId, rashid.id);
        expect(classified.suggestedCustomerName?.toLowerCase(), 'rashid');
        expect(
          AdminNoteParser.extractAttributionNames('Ye Rashid ke paise hain'),
          contains('Rashid'),
        );
      },
    );
  });

  group('Report save PDF / Gallery', () {
    test(
      'Save Both writes PDF and one PNG per page from same snapshot',
      () async {
        final harness = await TestDbHarness.create();
        addTearDown(harness.dispose);
        final day = DateTime(2026, 10, 11);
        await harness.receipts.appendImport(
          accountingDate: day,
          source: 'phase12',
          drafts: [
            for (var i = 0; i < 3; i++)
              ReceiptImportDraft(
                transactionId: 'M_$i',
                bankName: 'HBL',
                amount: 1000 + i.toDouble(),
                mappedAccountId: DefaultOfficeAccountIds.mutalib,
                receiptType: DbReceiptType.received,
              ),
          ],
        );

        final query = ReportQueryService(
          receipts: harness.receipts,
          offices: OfficeAccountRepository(harness.database),
          customers: CustomerRepository(harness.database),
          dealers: DealerRepository(harness.database),
        );
        final fakePng = Uint8List.fromList([137, 80, 78, 71]);
        final raster = _FakeRasterizer([fakePng, fakePng]);
        final gallery = _FakeGallery();
        String? pickedName;
        final service = ReportSaveService(
          query: query,
          pdfBuilder: PdfReportBuilder(),
          rasterizer: raster,
          gallerySaver: gallery,
          pdfDestinationPicker:
              ({required suggestedFileName, required pdfBytes}) async {
                pickedName = suggestedFileName;
                expect(pdfBytes.length, greaterThan(100));
                return 'content://user/chosen/$suggestedFileName';
              },
        );

        final outcome = await service.save(
          criteria: ReportCriteria(
            kind: ReportKind.mutalib,
            accountingDate: day,
            mappedAccountId: DefaultOfficeAccountIds.mutalib,
          ),
          mode: ReportSaveMode.pdfAndGallery,
        );

        expect(outcome.pdfSaved, isTrue);
        expect(outcome.pdfCancelled, isFalse);
        expect(pickedName, endsWith('.pdf'));
        expect(outcome.galleryPagesSaved, 2);
        expect(outcome.galleryFileNames, hasLength(2));
        expect(outcome.galleryFileNames.first, contains('Page_01'));
        expect(outcome.galleryFileNames.last, contains('Page_02'));
        expect(outcome.bothSucceeded, isTrue);
        expect(gallery.album, 'AI Bank Receipt Manager');
        expect(raster.lastPdfBytes, isNotNull);
      },
    );

    test(
      'PDF picker cancel does not save PDF or Gallery for Save Both',
      () async {
        final harness = await TestDbHarness.create();
        addTearDown(harness.dispose);
        final day = DateTime(2026, 10, 11);
        await harness.receipts.appendImport(
          accountingDate: day,
          source: 'phase12',
          drafts: [
            ReceiptImportDraft(
              transactionId: 'C1',
              bankName: 'HBL',
              amount: 500,
              receiptType: DbReceiptType.received,
            ),
          ],
        );

        final gallery = _FakeGallery();
        final service = ReportSaveService(
          query: ReportQueryService(
            receipts: harness.receipts,
            offices: OfficeAccountRepository(harness.database),
            customers: CustomerRepository(harness.database),
            dealers: DealerRepository(harness.database),
          ),
          rasterizer: _FakeRasterizer([
            Uint8List.fromList([1]),
          ]),
          gallerySaver: gallery,
          pdfDestinationPicker:
              ({required suggestedFileName, required pdfBytes}) async => null,
        );

        final outcome = await service.save(
          criteria: ReportCriteria(
            kind: ReportKind.dailyReceipt,
            accountingDate: day,
          ),
          mode: ReportSaveMode.pdfAndGallery,
        );

        expect(outcome.pdfCancelled, isTrue);
        expect(outcome.pdfSaved, isFalse);
        expect(outcome.galleryPagesSaved, 0);
        expect(gallery.savedNames, isEmpty);
        expect(outcome.anySucceeded, isFalse);
      },
    );

    test('export path does not mutate Entered ticks', () async {
      final harness = await TestDbHarness.create();
      addTearDown(harness.dispose);
      final day = DateTime(2026, 10, 11);
      await harness.receipts.appendImport(
        accountingDate: day,
        source: 'phase12',
        drafts: [
          for (var i = 0; i < 2; i++)
            ReceiptImportDraft(
              transactionId: 'E_$i',
              bankName: 'HBL',
              amount: 700,
              receiptType: DbReceiptType.received,
            ),
        ],
      );
      final rows = await harness.receipts.listByAccountingDate(day);
      await harness.receipts.markEntered(
        id: rows.first.id,
        enteredBy: 'tester',
      );
      final before = await harness.receipts.getById(rows.first.id);

      final service = ReportSaveService(
        query: ReportQueryService(
          receipts: harness.receipts,
          offices: OfficeAccountRepository(harness.database),
          customers: CustomerRepository(harness.database),
          dealers: DealerRepository(harness.database),
        ),
        rasterizer: _FakeRasterizer([
          Uint8List.fromList([9]),
        ]),
        gallerySaver: _FakeGallery(),
        pdfDestinationPicker:
            ({required suggestedFileName, required pdfBytes}) async =>
                'content://x/$suggestedFileName',
      );
      await service.save(
        criteria: ReportCriteria(
          kind: ReportKind.dailyReceipt,
          accountingDate: day,
        ),
        mode: ReportSaveMode.pdfAndGallery,
      );

      final after = await harness.receipts.getById(rows.first.id);
      expect(after!.entryStatus, DbEntryStatus.entered);
      expect(after.enteredAt, before!.enteredAt);
    });
  });
}

class _FakeRasterizer implements PdfPageRasterizer {
  _FakeRasterizer(this.pages);
  final List<Uint8List> pages;
  Uint8List? lastPdfBytes;

  @override
  Future<List<Uint8List>> rasterizePages(
    Uint8List pdfBytes, {
    double dpi = 144,
  }) async {
    lastPdfBytes = pdfBytes;
    return pages;
  }
}

class _FakeGallery implements GalleryImageSaver {
  final savedNames = <String>[];
  String? album;

  @override
  Future<bool> hasAccess() async => true;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<void> savePng({
    required Uint8List bytes,
    required String fileName,
    required String album,
  }) async {
    this.album = album;
    savedNames.add('$fileName.png');
  }
}
