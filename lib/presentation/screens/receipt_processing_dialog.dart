import 'dart:io';

import 'package:ai_bank_receipt_manager/application/classification/business_classification_service.dart';
import 'package:ai_bank_receipt_manager/application/import/batch_import_service.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/data/groq/groq_errors.dart';
import 'package:ai_bank_receipt_manager/data/groq/receipt_extraction.dart';
import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full receipt review result after user confirms processing.
class ReceiptProcessingResult {
  const ReceiptProcessingResult({
    required this.extraction,
    required this.mappedAccountId,
    required this.customerId,
    required this.dealerId,
    required this.receiptType,
    required this.reviewStatus,
  });

  final ReceiptExtraction extraction;
  final String? mappedAccountId;
  final String? customerId;
  final String? dealerId;
  final DbReceiptType receiptType;
  final DbReviewStatus reviewStatus;
}

Future<BatchItemReviewOutcome?> showReceiptProcessingDialog({
  required BuildContext context,
  required WidgetRef ref,
  required ReceiptExtraction initial,
  required String imagePath,
  GroqFailure? failure,
  String? rawJson,
  String title = 'Receipt Processing',
}) async {
  final result = await showDialog<ReceiptProcessingResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReceiptProcessingDialog(
      initial: initial,
      imagePath: imagePath,
      failure: failure,
      rawJson: rawJson,
      title: title,
    ),
  );
  if (result == null) {
    return null;
  }
  return BatchItemReviewOutcome(
    extraction: result.extraction,
    adminMessage: result.extraction.adminMessage,
    mappedAccountId: result.mappedAccountId,
    customerId: result.customerId,
    dealerId: result.dealerId,
    receiptType: result.receiptType,
    reviewStatus: result.reviewStatus,
  );
}

class ReceiptProcessingDialog extends ConsumerStatefulWidget {
  const ReceiptProcessingDialog({
    required this.initial,
    required this.imagePath,
    this.failure,
    this.rawJson,
    this.title = 'Receipt Processing',
    super.key,
  });

  final ReceiptExtraction initial;
  final String imagePath;
  final GroqFailure? failure;
  final String? rawJson;
  final String title;

  @override
  ConsumerState<ReceiptProcessingDialog> createState() =>
      _ReceiptProcessingDialogState();
}

class _ReceiptProcessingDialogState
    extends ConsumerState<ReceiptProcessingDialog> {
  late final TextEditingController _bank;
  late final TextEditingController _sender;
  late final TextEditingController _receiver;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _reference;
  late final TextEditingController _dateTime;
  late final TextEditingController _whatsapp;
  late final TextEditingController _admin;

  String? _officeId;
  String? _customerId;
  String? _dealerId;
  DbReceiptType _direction = DbReceiptType.unknown;
  ClassificationResult? _classification;
  var _loading = true;
  String? _error;

  List<OfficeAccountRecord> _offices = const [];
  List<CustomerRecord> _customers = const [];
  List<DealerRecord> _dealers = const [];

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
    _bootstrap();
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

  Future<void> _bootstrap() async {
    try {
      final officesRepo = await ref.read(
        officeAccountRepositoryProvider.future,
      );
      final customersRepo = await ref.read(customerRepositoryProvider.future);
      final dealersRepo = await ref.read(dealerRepositoryProvider.future);
      _offices = await officesRepo.listSelectableForNewEntries();
      _customers = await customersRepo.list();
      _dealers = await dealersRepo.list();
      final aliases = <String, List<OfficeAccountAliasRecord>>{};
      for (final o in _offices) {
        aliases[o.id] = await officesRepo.listAliases(o.id);
      }
      final customerAliases = <String, List<PartyAliasRecord>>{};
      for (final c in _customers) {
        customerAliases[c.id] = await customersRepo.listAliases(c.id);
      }
      final dealerAliases = <String, List<PartyAliasRecord>>{};
      for (final d in _dealers) {
        dealerAliases[d.id] = await dealersRepo.listAliases(d.id);
      }

      final classified = BusinessClassificationService().classify(
        input: ClassificationInput(
          bankSenderName: widget.initial.senderBankAccountName,
          bankReceiverName: widget.initial.receiverBankAccountName,
          adminMessage: widget.initial.adminMessage,
          whatsappSender: widget.initial.whatsappSender,
          bankDirectionHint: _parseDirection(widget.initial.bankDirectionHint),
          suggestedCustomerName: widget.initial.suggestedCustomerName,
          suggestedDealerName: widget.initial.suggestedDealerName,
          suggestedOfficeAccountName: widget.initial.suggestedOfficeAccountName,
        ),
        accounts: _offices,
        accountAliases: aliases,
        customers: _customers,
        customerAliases: customerAliases,
        dealers: _dealers,
        dealerAliases: dealerAliases,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _classification = classified;
        _officeId = classified.officeAccountId;
        _customerId = classified.customerId;
        _dealerId = classified.dealerId;
        _direction = classified.proposedReceiptType;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  DbReceiptType? _parseDirection(String? hint) {
    if (hint == null) {
      return null;
    }
    final lower = hint.toLowerCase();
    if (lower.contains('credit') ||
        lower.contains('received') ||
        lower.contains('incoming')) {
      return DbReceiptType.received;
    }
    if (lower.contains('debit') ||
        lower.contains('sent') ||
        lower.contains('outgoing')) {
      return DbReceiptType.sent;
    }
    return null;
  }

  void _reclassifyFromFields() {
    // Lightweight re-run when admin note / bank names change.
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountText = _amount.text.trim();
    final amount = amountText.isEmpty
        ? null
        : double.tryParse(amountText.replaceAll(',', ''));
    String? officeName;
    for (final o in _offices) {
      if (o.id == _officeId) {
        officeName = o.displayName;
        break;
      }
    }
    String? customerName;
    for (final c in _customers) {
      if (c.id == _customerId) {
        customerName = c.name;
        break;
      }
    }
    final suggestedCustomer = _classification?.suggestedCustomerName;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.failure != null)
                      NoticePanel(
                        message:
                            'AI extraction failed: ${widget.failure!.message}. '
                            'Image is preserved — enter fields manually.',
                        icon: Icons.warning_amber_outlined,
                        foreground: theme.colorScheme.onErrorContainer,
                        background: theme.colorScheme.errorContainer,
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    const SizedBox(height: 8),
                    if (widget.imagePath.isNotEmpty &&
                        File(widget.imagePath).existsSync())
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(widget.imagePath),
                          height: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Bank identities', style: theme.textTheme.titleSmall),
                    Text(
                      'These are the names printed on the bank receipt — '
                      'separate from the accounting customer.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    _field(_bank, 'Bank name'),
                    _field(_sender, 'Bank sender'),
                    _field(_receiver, 'Bank receiver'),
                    _field(_amount, 'Amount', keyboard: TextInputType.number),
                    if (amount != null)
                      Text(
                        formatPkr(amount),
                        style: theme.textTheme.titleMedium,
                      ),
                    _field(_currency, 'Currency'),
                    _field(_reference, 'Transaction reference'),
                    _field(_dateTime, 'Transaction date/time'),
                    const SizedBox(height: 8),
                    Text('WhatsApp', style: theme.textTheme.titleSmall),
                    _field(_whatsapp, 'WhatsApp sender (forwarder)'),
                    _field(_admin, 'WhatsApp admin note'),
                    TextButton(
                      onPressed: _reclassifyFromFields,
                      child: const Text('Re-match office / parties'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accounting attribution',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      'Office: ${officeName ?? 'Unassigned'} · '
                      'Direction: ${_directionLabel(_direction)} · '
                      'Status: Pending',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (suggestedCustomer != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Suggested customer: $suggestedCustomer'
                        '${_classification?.customerConfirmationRequired == true ? ' — confirmation required' : ''}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (_classification != null) ...[
                      for (final reason in _classification!.reasons.take(4))
                        Text('• $reason', style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      // ignore: deprecated_member_use
                      value: _officeId,
                      decoration: const InputDecoration(
                        labelText: 'Office account',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Unassigned'),
                        ),
                        for (final o in _offices)
                          DropdownMenuItem(
                            value: o.id,
                            child: Text(o.displayName),
                          ),
                      ],
                      onChanged: (v) => setState(() => _officeId = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<DbReceiptType>(
                      // ignore: deprecated_member_use
                      value: _direction,
                      decoration: const InputDecoration(
                        labelText: 'Direction',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: DbReceiptType.received,
                          child: Text('Incoming'),
                        ),
                        DropdownMenuItem(
                          value: DbReceiptType.sent,
                          child: Text('Outgoing'),
                        ),
                        DropdownMenuItem(
                          value: DbReceiptType.unknown,
                          child: Text('Unknown'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _direction = v);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      // ignore: deprecated_member_use
                      value: _customerId,
                      decoration: InputDecoration(
                        labelText:
                            customerName == null && suggestedCustomer != null
                            ? 'Customer (suggested: $suggestedCustomer)'
                            : 'Related customer',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('None — select later'),
                        ),
                        for (final c in _customers)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => _customerId = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      // ignore: deprecated_member_use
                      value: _dealerId,
                      decoration: const InputDecoration(
                        labelText: 'Related dealer',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('None'),
                        ),
                        for (final d in _dealers)
                          DropdownMenuItem(value: d.id, child: Text(d.name)),
                      ],
                      onChanged: (v) => setState(() => _dealerId = v),
                    ),
                    if (widget.initial.overallConfidence != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'AI confidence: '
                        '${(widget.initial.overallConfidence! * 100).toStringAsFixed(0)}%',
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
          onPressed: _loading
              ? null
              : () {
                  final amountText = _amount.text.trim();
                  final needsReview =
                      _classification?.needsReview == true ||
                      _officeId == null ||
                      (_classification?.customerConfirmationRequired == true &&
                          _customerId == null &&
                          _direction == DbReceiptType.received);
                  Navigator.pop(
                    context,
                    ReceiptProcessingResult(
                      extraction: ReceiptExtraction(
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
                        suggestedCustomerName:
                            _classification?.suggestedCustomerName ??
                            widget.initial.suggestedCustomerName,
                        suggestedDealerName:
                            _classification?.suggestedDealerName ??
                            widget.initial.suggestedDealerName,
                        suggestedOfficeAccountName:
                            widget.initial.suggestedOfficeAccountName,
                        bankDirectionHint: widget.initial.bankDirectionHint,
                        maskedAccountNumbers:
                            widget.initial.maskedAccountNumbers,
                        uncertainFields: widget.initial.uncertainFields,
                        missingFields: widget.initial.missingFields,
                        fieldConfidence: widget.initial.fieldConfidence,
                        overallConfidence: widget.initial.overallConfidence,
                      ),
                      mappedAccountId: _officeId,
                      customerId: _customerId,
                      dealerId: _dealerId,
                      receiptType: _direction,
                      reviewStatus: needsReview
                          ? DbReviewStatus.pendingReview
                          : DbReviewStatus.approved,
                    ),
                  );
                },
          child: const Text('Confirm & save'),
        ),
      ],
    );
  }

  String _directionLabel(DbReceiptType type) => switch (type) {
    DbReceiptType.received => 'Incoming',
    DbReceiptType.sent => 'Outgoing',
    DbReceiptType.unknown => 'Unknown',
  };

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
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
