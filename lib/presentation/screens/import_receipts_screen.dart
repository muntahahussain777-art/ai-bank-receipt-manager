import 'dart:async';

import 'package:ai_bank_receipt_manager/application/groq/receipt_vision_service.dart';
import 'package:ai_bank_receipt_manager/application/import/batch_import_service.dart';
import 'package:ai_bank_receipt_manager/application/import/receipt_ingestion.dart';
import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class ImportReceiptsScreen extends ConsumerStatefulWidget {
  const ImportReceiptsScreen({super.key});

  @override
  ConsumerState<ImportReceiptsScreen> createState() =>
      _ImportReceiptsScreenState();
}

class _ImportReceiptsScreenState extends ConsumerState<ImportReceiptsScreen> {
  bool _busy = false;
  String? _status;
  StreamSubscription<List<IngestedFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForShares());
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Future<void> _listenForShares() async {
    final source = ref.read(androidShareIngestionProvider);
    final initial = await source.getInitialFiles();
    if (initial.isNotEmpty && mounted) {
      await _runBatch(initial, sourceLabel: 'android_share');
    }
    _shareSub = source.watchIncomingFiles().listen((files) {
      if (files.isNotEmpty) {
        _runBatch(files, sourceLabel: 'android_share');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedAccountingDateProvider);
    final batchesAsync = ref.watch(recentImportBatchesProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        NoticePanel(
          message:
              'Share from WhatsApp, pick gallery/camera/PDF, or enter manually. '
              'Accounting date is ${formatAccountingDate(date)} (change it for '
              'historical import). Images are kept even if AI fails. Personal '
              'WhatsApp groups are not read automatically.',
          icon: Icons.image_outlined,
          foreground: theme.colorScheme.onSecondaryContainer,
          background: theme.colorScheme.secondaryContainer,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          ref
                              .read(selectedAccountingDateProvider.notifier)
                              .select(picked);
                        }
                      },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Accounting: ${formatAccountingDate(date)}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_status != null) ...[
          Text(_status!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
        ],
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _pickGallery(multi: false),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Gallery'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _pickGallery(multi: true),
              icon: const Icon(Icons.collections_outlined),
              label: const Text('Batch gallery'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _pickCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _pickPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _manualEntry,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Manual entry'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: 'Import batches',
          subtitle:
              'Append-only. Midday and evening imports on the same day both keep.',
        ),
        const SizedBox(height: 12),
        batchesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (batches) {
            if (batches.isEmpty) {
              return const EmptyState(message: 'No import batches yet.');
            }
            return Column(
              children: [
                for (final batch in batches) ...[
                  _BatchCard(batch: batch),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickGallery({required bool multi}) async {
    final picker = ImagePicker();
    final files = <IngestedFile>[];
    if (multi) {
      final picked = await picker.pickMultiImage();
      for (final x in picked) {
        files.add(
          IngestedFile(
            path: x.path,
            sourceKind: 'gallery',
            mimeType: x.mimeType,
            displayName: x.name,
          ),
        );
      }
    } else {
      final x = await picker.pickImage(source: ImageSource.gallery);
      if (x != null) {
        files.add(
          IngestedFile(
            path: x.path,
            sourceKind: 'gallery',
            mimeType: x.mimeType,
            displayName: x.name,
          ),
        );
      }
    }
    if (files.isNotEmpty) {
      await _runBatch(files, sourceLabel: 'gallery');
    }
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera);
    if (x == null) {
      return;
    }
    await _runBatch([
      IngestedFile(
        path: x.path,
        sourceKind: 'camera',
        mimeType: x.mimeType,
        displayName: x.name,
      ),
    ], sourceLabel: 'camera');
  }

  Future<void> _pickPdf() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked.isEmpty) {
      return;
    }
    final files = <IngestedFile>[
      for (final f in picked)
        if (f.path != null)
          IngestedFile(
            path: f.path!,
            sourceKind: 'pdf',
            mimeType: 'application/pdf',
            displayName: f.name,
          ),
    ];
    if (files.isNotEmpty) {
      await _runBatch(files, sourceLabel: 'pdf');
    }
  }

  Future<void> _manualEntry() async {
    final extraction = await showDialog<ReceiptExtraction>(
      context: context,
      builder: (context) => const _ExtractionReviewDialog(
        initial: ReceiptExtraction(currency: 'PKR'),
        imagePath: '(no image)',
        title: 'Manual receipt entry',
      ),
    );
    if (extraction == null) {
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Saving manual entry…';
    });
    try {
      final service = await ref.read(batchImportServiceProvider.future);
      await service.saveManualEntry(
        accountingDate: ref.read(selectedAccountingDateProvider),
        fields: extraction,
        adminMessage: extraction.adminMessage,
      );
      ref.invalidate(recentImportBatchesProvider);
      setState(() => _status = 'Manual receipt saved.');
    } catch (error) {
      setState(() => _status = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runBatch(
    List<IngestedFile> files, {
    required String sourceLabel,
  }) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Authorizing ${files.length} file(s)…';
    });

    try {
      final authorized = await _confirmUpload(files.length);
      if (!authorized) {
        setState(() => _status = 'Import cancelled — nothing uploaded.');
        return;
      }

      final adminNote = await _optionalSharedAdminNote();
      final groupMap = await _optionalGrouping(files);

      final service = await ref.read(batchImportServiceProvider.future);
      final accountingDate = ref.read(selectedAccountingDateProvider);

      setState(() => _status = 'Saving originals to device storage…');
      final batch = await service.enqueueFiles(
        accountingDate: accountingDate,
        files: files,
        source: sourceLabel,
        sharedAdminNote: adminNote,
        groupIdsByPath: groupMap,
      );

      setState(() => _status = 'Processing batch ${batch.id.substring(0, 8)}…');
      await service.processQueued(
        batchId: batch.id,
        userAuthorizedUpload: true,
        onNeedsReview: (item, vision, duplicates) async {
          if (!context.mounted) {
            return null;
          }
          return _reviewItem(item, vision, duplicates);
        },
      );

      final refreshed = await ref
          .read(importQueueRepositoryProvider.future)
          .then((repo) => repo.getBatch(batch.id));
      ref.invalidate(recentImportBatchesProvider);
      setState(() {
        _status =
            'Batch done — success ${refreshed?.successCount ?? 0}, '
            'failed ${refreshed?.failedCount ?? 0}, '
            'duplicates ${refreshed?.duplicateCount ?? 0}, '
            'pending ${refreshed?.pendingReviewCount ?? 0}.';
      });
    } on GroqFailure catch (failure) {
      setState(() => _status = failure.message);
    } catch (error) {
      setState(() => _status = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<BatchItemReviewOutcome?> _reviewItem(
    ImportQueueItemRecord item,
    VisionJobResult? vision,
    List<DuplicateMatch> duplicates,
  ) async {
    final initial =
        vision?.extraction ??
        ReceiptExtraction(
          adminMessage: item.adminNoteOverride,
          currency: 'PKR',
          missingFields: const ['bankName', 'amount', 'transactionReference'],
        );

    DuplicateDecision decision = DuplicateDecision.keepSeparate;
    String? duplicateOf;
    if (duplicates.isNotEmpty) {
      final choice = await showDialog<_DuplicateChoice>(
        context: context,
        builder: (context) => _DuplicateDialog(matches: duplicates),
      );
      if (choice == null) {
        return null;
      }
      if (choice.decision == DuplicateDecision.skip) {
        return BatchItemReviewOutcome(
          extraction: initial,
          duplicateDecision: DuplicateDecision.skip,
          duplicateOfReceiptId: choice.receiptId,
        );
      }
      if (choice.decision == DuplicateDecision.reviewExisting) {
        // Keep as skip for queue accounting; user was shown the existing id.
        return BatchItemReviewOutcome(
          extraction: initial,
          duplicateDecision: DuplicateDecision.skip,
          duplicateOfReceiptId: choice.receiptId,
        );
      }
      decision = DuplicateDecision.keepSeparate;
      duplicateOf = choice.receiptId;
    }

    if (!mounted) {
      return null;
    }

    final corrected = await showDialog<ReceiptExtraction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ExtractionReviewDialog(
        initial: initial,
        imagePath: item.storedPath,
        failure: vision?.failure,
        rawJson: vision?.extractionRecord.rawAiJson,
        title: item.mimeType?.contains('pdf') == true
            ? 'PDF receipt — enter fields'
            : 'Review extraction',
      ),
    );
    if (corrected == null) {
      return null;
    }
    return BatchItemReviewOutcome(
      extraction: corrected,
      adminMessage: corrected.adminMessage,
      duplicateDecision: decision,
      duplicateOfReceiptId: duplicateOf,
    );
  }

  Future<bool> _confirmUpload(int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Authorize upload'),
        content: Text(
          'Send $count file(s) to Groq Vision for extraction? '
          'Files are copied to this device first. Deny to cancel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Authorize'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _optionalSharedAdminNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WhatsApp admin note (optional)'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Customer / dealer note for this batch',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) {
      return null;
    }
    return result;
  }

  Future<Map<String, String>?> _optionalGrouping(
    List<IngestedFile> files,
  ) async {
    if (files.length < 2) {
      return null;
    }
    final group = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Group images?'),
        content: const Text(
          'If several images belong to one bank transaction, group them '
          'before processing. Separate transactions must stay separate '
          'reviewed receipts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Separate'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Group all as one'),
          ),
        ],
      ),
    );
    if (group != true) {
      return null;
    }
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return {for (final f in files) f.path: id};
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});

  final ImportBatchRecord batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batch ${batch.id.substring(0, 8)} · ${batch.source}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Accounting ${formatAccountingDate(batch.accountingDate)} · '
            'Imported ${batch.importedAt.toLocal()}',
          ),
          const SizedBox(height: 4),
          Text(
            'Files ${batch.fileCount} · OK ${batch.successCount} · '
            'Failed ${batch.failedCount} · Dup ${batch.duplicateCount} · '
            'Pending ${batch.pendingReviewCount}',
          ),
          Text('Status: ${batch.batchStatus.storageValue}'),
        ],
      ),
    );
  }
}

class _DuplicateChoice {
  const _DuplicateChoice(this.decision, this.receiptId);
  final DuplicateDecision decision;
  final String? receiptId;
}

class _DuplicateDialog extends StatelessWidget {
  const _DuplicateDialog({required this.matches});

  final List<DuplicateMatch> matches;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Possible duplicate'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Matching image hash, bank, reference, date, or amount was found. '
              'Nothing will be deleted automatically.',
            ),
            const SizedBox(height: 12),
            for (final match in matches.take(5)) ...[
              Text(
                '${match.existing.bankName} · ${match.existing.amount} · '
                '${match.existing.transactionId ?? 'no ref'}',
              ),
              Text(
                'Reasons: ${match.reasons.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _DuplicateChoice(DuplicateDecision.skip, matches.first.existing.id),
          ),
          child: const Text('Skip duplicate'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _DuplicateChoice(
              DuplicateDecision.reviewExisting,
              matches.first.existing.id,
            ),
          ),
          child: const Text('Review existing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _DuplicateChoice(
              DuplicateDecision.keepSeparate,
              matches.first.existing.id,
            ),
          ),
          child: const Text('Keep separate'),
        ),
      ],
    );
  }
}

class _ExtractionReviewDialog extends StatefulWidget {
  const _ExtractionReviewDialog({
    required this.initial,
    required this.imagePath,
    this.failure,
    this.rawJson,
    this.title = 'Review AI extraction',
  });

  final ReceiptExtraction initial;
  final String imagePath;
  final GroqFailure? failure;
  final String? rawJson;
  final String title;

  @override
  State<_ExtractionReviewDialog> createState() =>
      _ExtractionReviewDialogState();
}

class _ExtractionReviewDialogState extends State<_ExtractionReviewDialog> {
  late final TextEditingController _bank;
  late final TextEditingController _sender;
  late final TextEditingController _receiver;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _reference;
  late final TextEditingController _dateTime;
  late final TextEditingController _whatsapp;
  late final TextEditingController _admin;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _bank = TextEditingController(text: i.bankName ?? '');
    _sender = TextEditingController(text: i.senderBankAccountName ?? '');
    _receiver = TextEditingController(text: i.receiverBankAccountName ?? '');
    _amount = TextEditingController(
      text: i.amount == null ? '' : i.amount!.toString(),
    );
    _currency = TextEditingController(text: i.currency ?? 'PKR');
    _reference = TextEditingController(text: i.transactionReference ?? '');
    _dateTime = TextEditingController(text: i.transactionDateTimeRaw ?? '');
    _whatsapp = TextEditingController(text: i.whatsappSender ?? '');
    _admin = TextEditingController(text: i.adminMessage ?? '');
  }

  @override
  void dispose() {
    _bank.dispose();
    _sender.dispose();
    _receiver.dispose();
    _amount.dispose();
    _currency.dispose();
    _reference.dispose();
    _dateTime.dispose();
    _whatsapp.dispose();
    _admin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.failure != null)
                NoticePanel(
                  message:
                      'AI failed (${widget.failure!.kind.name}): '
                      '${widget.failure!.message}. Image preserved.',
                  icon: Icons.warning_amber_outlined,
                  foreground: theme.colorScheme.onErrorContainer,
                  background: theme.colorScheme.errorContainer,
                ),
              const SizedBox(height: 8),
              Text(
                'File: ${widget.imagePath}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'WhatsApp sender is not the bank sender.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _field(_bank, 'Bank name'),
              _field(_sender, 'Sender bank account name'),
              _field(_receiver, 'Receiver bank account name'),
              _field(_amount, 'Amount', keyboard: TextInputType.number),
              _field(_currency, 'Currency'),
              _field(_reference, 'Transaction reference'),
              _field(_dateTime, 'Transaction date/time'),
              _field(_whatsapp, 'WhatsApp sender (if visible)'),
              _field(_admin, 'WhatsApp admin note'),
              if (widget.rawJson != null) ...[
                const SizedBox(height: 8),
                Text('Raw AI JSON', style: theme.textTheme.labelLarge),
                SelectableText(
                  widget.rawJson!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final amountText = _amount.text.trim();
            Navigator.pop(
              context,
              ReceiptExtraction(
                bankName: _emptyToNull(_bank.text),
                senderBankAccountName: _emptyToNull(_sender.text),
                receiverBankAccountName: _emptyToNull(_receiver.text),
                amount: amountText.isEmpty
                    ? null
                    : double.tryParse(amountText.replaceAll(',', '')),
                currency: _emptyToNull(_currency.text),
                transactionReference: _emptyToNull(_reference.text),
                transactionDateTimeRaw: _emptyToNull(_dateTime.text),
                whatsappSender: _emptyToNull(_whatsapp.text),
                adminMessage: _emptyToNull(_admin.text),
                maskedAccountNumbers: widget.initial.maskedAccountNumbers,
                uncertainFields: widget.initial.uncertainFields,
                missingFields: widget.initial.missingFields,
                fieldConfidence: widget.initial.fieldConfidence,
                overallConfidence: widget.initial.overallConfidence,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
