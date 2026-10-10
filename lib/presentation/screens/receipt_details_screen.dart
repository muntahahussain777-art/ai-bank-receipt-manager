import 'dart:io';

import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/desk_providers.dart';
import 'package:ai_bank_receipt_manager/application/reconciliation/build_reconciliation_preview.dart';
import 'package:ai_bank_receipt_manager/application/reconciliation/financial_change_detector.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/core/theme/app_theme.dart';
import 'package:ai_bank_receipt_manager/domain/entities/receipt.dart';
import 'package:ai_bank_receipt_manager/domain/enums/entry_status.dart';
import 'package:ai_bank_receipt_manager/domain/enums/party_kind.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/reconciliation_dialog.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/status_chip.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReceiptDetailsScreen extends ConsumerStatefulWidget {
  const ReceiptDetailsScreen({
    required this.receiptId,
    required this.startInEdit,
    super.key,
  });

  final String receiptId;
  final bool startInEdit;

  @override
  ConsumerState<ReceiptDetailsScreen> createState() =>
      _ReceiptDetailsScreenState();
}

class _ReceiptDetailsScreenState extends ConsumerState<ReceiptDetailsScreen> {
  late final TextEditingController _amount;
  late final TextEditingController _party;
  late final TextEditingController _reference;
  late final TextEditingController _admin;
  late final TextEditingController _winforms;
  late bool _editing;
  String? _amountError;
  var _controllersReady = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.startInEdit;
    _amount = TextEditingController();
    _party = TextEditingController();
    _reference = TextEditingController();
    _admin = TextEditingController();
    _winforms = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _party.dispose();
    _reference.dispose();
    _admin.dispose();
    _winforms.dispose();
    super.dispose();
  }

  void _hydrate(Receipt receipt) {
    if (_controllersReady) {
      return;
    }
    _amount.text = _plainAmount(receipt.amount);
    _party.text = receipt.partyName;
    _reference.text = receipt.reference == '(no reference)'
        ? ''
        : receipt.reference;
    _admin.text = receipt.adminNote;
    _winforms.text = receipt.winformsReference ?? '';
    _controllersReady = true;
  }

  @override
  Widget build(BuildContext context) {
    final receiptAsync = ref.watch(storedReceiptByIdProvider(widget.receiptId));
    return receiptAsync.when(
      loading: () => const PageScroll(children: [LinearProgressIndicator()]),
      error: (e, _) => PageScroll(children: [Text('$e')]),
      data: (receipt) {
        if (receipt == null) {
          return const PageScroll(
            children: [
              EmptyState(message: 'Receipt not found in SQLite storage.'),
            ],
          );
        }
        _hydrate(receipt);
        final theme = Theme.of(context);
        final colors = statusColorsOf(context);
        return PageScroll(
          children: [
            NoticePanel(
              message: BusinessRules.winFormsSafety,
              icon: Icons.info_outline,
              foreground: colors.reconciliation,
              background: colors.reconciliationContainer,
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      StatusChip(status: receipt.status),
                      InfoPill(label: receipt.bankName),
                      if (receipt.entryStatusEntered)
                        const InfoPill(label: 'WinForms tick: Entered'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(formatPkr(receipt.amount), style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  DefinitionBlock(label: 'Bank', value: receipt.bankName),
                  DefinitionBlock(
                    label: 'Sender',
                    value: receipt.bankSenderName ?? '—',
                  ),
                  DefinitionBlock(
                    label: 'Receiver',
                    value: receipt.bankReceiverName ?? '—',
                  ),
                  DefinitionBlock(
                    label: receipt.partyKind.label,
                    value: receipt.partyName,
                  ),
                  DefinitionBlock(
                    label: 'Office account',
                    value: receipt.officeDisplayLabel,
                  ),
                  DefinitionBlock(
                    label: 'Accounting date',
                    value: formatAccountingDate(receipt.accountingDate),
                  ),
                  DefinitionBlock(label: 'Reference', value: receipt.reference),
                  if (receipt.enteredAt != null)
                    DefinitionBlock(
                      label: 'Entered at',
                      value: receipt.enteredAt!.toLocal().toString(),
                    ),
                  if (receipt.originalImagePath != null) ...[
                    const SizedBox(height: 8),
                    Text('Original receipt', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (File(receipt.originalImagePath!).existsSync())
                      Image.file(
                        File(receipt.originalImagePath!),
                        height: 220,
                        fit: BoxFit.contain,
                      )
                    else
                      Text(receipt.originalImagePath!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin note', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    receipt.adminNote.isEmpty ? '—' : receipt.adminNote,
                  ),
                ],
              ),
            ),
            if (receipt.priorAmount != null) ...[
              const SizedBox(height: 12),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reconciliation required',
                      style: theme.textTheme.titleMedium,
                    ),
                    DefinitionBlock(
                      label: 'Old amount',
                      value: formatPkr(receipt.baselineAmount),
                    ),
                    DefinitionBlock(
                      label: 'New amount',
                      value: formatPkr(receipt.amount),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_editing) _editCard(receipt) else _viewActions(receipt),
          ],
        );
      },
    );
  }

  Widget _viewActions(Receipt receipt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _editing = true),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
        if (!receipt.entryStatusEntered)
          FilledButton.icon(
            onPressed: () => _markEntered(receipt),
            icon: const Icon(Icons.check),
            label: const Text('Mark Entered'),
          ),
        if (receipt.entryStatusEntered)
          OutlinedButton.icon(
            onPressed: () => _undoEntered(receipt),
            icon: const Icon(Icons.undo),
            label: const Text('Undo Entered'),
          ),
        if (receipt.status == EntryStatus.needsReconciliation)
          FilledButton.tonalIcon(
            onPressed: () => _confirmReconciliation(receipt),
            icon: const Icon(Icons.rule),
            label: const Text('Reconciliation Completed'),
          ),
        if (receipt.status == EntryStatus.needsReconciliation)
          OutlinedButton.icon(
            onPressed: () => _showAuditHistory(receipt),
            icon: const Icon(Icons.history),
            label: const Text('Audit history'),
          ),
        TextButton.icon(
          onPressed: () => _moveDate(receipt),
          icon: const Icon(Icons.event),
          label: const Text('Move date'),
        ),
      ],
    );
  }

  Widget _editCard(Receipt receipt) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit receipt', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            receipt.entryStatusEntered
                ? 'This row is Entered. Saving financial changes keeps the tick '
                    'and opens reconciliation.'
                : 'Changes are saved to SQLite. WinForms is never modified.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (Rs)',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _party,
            decoration: const InputDecoration(labelText: 'Customer or dealer'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(labelText: 'Transaction reference'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _admin,
            decoration: const InputDecoration(labelText: 'Admin note'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _winforms,
            decoration: const InputDecoration(
              labelText: 'Optional WinForms reference',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _saveEdit(receipt),
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () => _cancelEdit(receipt),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _cancelEdit(Receipt receipt) {
    _controllersReady = false;
    _hydrate(receipt);
    setState(() {
      _editing = false;
      _amountError = null;
    });
  }

  Future<void> _saveEdit(Receipt receipt) async {
    final parsed = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (parsed == null || parsed < 0) {
      setState(() => _amountError = 'Enter a valid amount.');
      return;
    }
    setState(() => _amountError = null);

    final newParty =
        _party.text.trim().isEmpty ? receipt.partyName : _party.text.trim();
    final newRef = _reference.text.trim().isEmpty
        ? null
        : _reference.text.trim();
    final oldRef = receipt.reference == '(no reference)'
        ? null
        : receipt.reference;

    final service = await ref.read(receiptEntryServiceProvider.future);
    final diffs = await service.previewFinancialEdit(
      id: receipt.id,
      patch: ReceiptFinancialPatch(
        amount: parsed,
        transactionId: newRef,
        clearTransactionId: newRef == null && oldRef != null,
        adminMessage: _admin.text.trim(),
        partyDisplayName: newParty,
      ),
    );

    var confirmed = true;
    if (receipt.entryStatusEntered && diffs.isNotEmpty) {
      final preview = buildReconciliationPreview(
        receipt: receipt,
        newAmount: parsed,
        newParty: newParty,
        newOfficeAccount: receipt.officeAccount,
        fieldDiffs: diffs,
      );
      if (!mounted) {
        return;
      }
      confirmed = await showReconciliationDialog(context, preview: preview);
      if (!confirmed || !mounted) {
        return;
      }
    }

    await service.applyFinancialEdit(
      id: receipt.id,
      newAmount: parsed,
      newPartyName: newParty,
      newAdminMessage: _admin.text.trim(),
      newTransactionId: newRef,
      clearTransactionId: newRef == null && oldRef != null,
      changedBy: 'desk',
      userConfirmedReconciliation: confirmed && diffs.isNotEmpty,
    );
    _controllersReady = false;
    setState(() => _editing = false);
    invalidateDeskProviders(ref);
    ref.invalidate(storedReceiptByIdProvider(widget.receiptId));
  }

  Future<void> _markEntered(Receipt receipt) async {
    final service = await ref.read(receiptEntryServiceProvider.future);
    try {
      await service.markEntered(
        id: receipt.id,
        enteredBy: 'desk',
        winformsReference: _winforms.text.trim().isEmpty
            ? null
            : _winforms.text.trim(),
      );
      invalidateDeskProviders(ref);
      ref.invalidate(storedReceiptByIdProvider(widget.receiptId));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _undoEntered(Receipt receipt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo Entered?'),
        content: const Text(
          'Confirm only if the WinForms row should no longer count as entered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final service = await ref.read(receiptEntryServiceProvider.future);
    await service.undoEntered(
      id: receipt.id,
      confirmed: true,
      changedBy: 'desk',
    );
    invalidateDeskProviders(ref);
    ref.invalidate(storedReceiptByIdProvider(widget.receiptId));
  }

  Future<void> _confirmReconciliation(Receipt receipt) async {
    final preview = buildReconciliationPreview(
      receipt: receipt,
      newAmount: receipt.amount,
      newParty: receipt.partyName,
      newOfficeAccount: receipt.officeAccount,
    );
    final confirmed = await showReconciliationDialog(
      context,
      preview: preview,
      confirmLabel: 'Reconciliation Completed',
    );
    if (!confirmed) {
      return;
    }
    final service = await ref.read(receiptEntryServiceProvider.future);
    await service.confirmReconciliationReviewed(
      id: receipt.id,
      reviewedBy: 'desk',
    );
    invalidateDeskProviders(ref);
    ref.invalidate(storedReceiptByIdProvider(widget.receiptId));
  }

  Future<void> _showAuditHistory(Receipt receipt) async {
    final repo = await ref.read(receiptRepositoryProvider.future);
    final audits = await repo.listAuditHistory(receipt.id);
    final cases = await repo.listReconciliationCases(receipt.id);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Audit history'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reconciliation cases: ${cases.length}'),
                for (final c in cases)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${c.kind.storageValue} · ${c.status.storageValue}\n'
                      '${c.reason}'
                      '${c.correctionNotes == null ? '' : '\nNotes: ${c.correctionNotes}'}',
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Field audits: ${audits.length}'),
                for (final a in audits)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${a.fieldName}: ${a.oldValue ?? '—'} → ${a.newValue ?? '—'}'
                      '${a.reason == null ? '' : '\n${a.reason}'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveDate(Receipt receipt) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: receipt.accountingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    final service = await ref.read(receiptEntryServiceProvider.future);
    if (receipt.entryStatusEntered) {
      final diffs = await service.previewFinancialEdit(
        id: receipt.id,
        patch: ReceiptFinancialPatch(accountingDate: picked),
      );
      final preview = buildReconciliationPreview(
        receipt: receipt,
        newAmount: receipt.amount,
        newParty: receipt.partyName,
        newOfficeAccount: receipt.officeAccount,
        fieldDiffs: diffs,
      );
      if (!mounted) {
        return;
      }
      final confirmed = await showReconciliationDialog(
        context,
        preview: preview,
      );
      if (!confirmed || !mounted) {
        return;
      }
      await service.applyFinancialEdit(
        id: receipt.id,
        newAccountingDate: picked,
        changedBy: 'desk',
        userConfirmedReconciliation: true,
      );
    } else {
      final repo = await ref.read(receiptRepositoryProvider.future);
      await repo.moveAccountingDate(
        id: receipt.id,
        newAccountingDate: picked,
        changedBy: 'desk',
      );
    }
    invalidateDeskProviders(ref);
    ref.invalidate(storedReceiptByIdProvider(widget.receiptId));
  }

  String _plainAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.round().toString();
    }
    return amount.toString();
  }
}
