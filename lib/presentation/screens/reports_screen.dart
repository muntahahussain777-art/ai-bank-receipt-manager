import 'package:ai_bank_receipt_manager/application/providers/app_providers.dart';
import 'package:ai_bank_receipt_manager/application/providers/database_providers.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_export_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_models.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_query_service.dart';
import 'package:ai_bank_receipt_manager/application/reports/report_save_service.dart';
import 'package:ai_bank_receipt_manager/core/formatting/date_format.dart';
import 'package:ai_bank_receipt_manager/core/formatting/money_format.dart';
import 'package:ai_bank_receipt_manager/domain/rules/business_rules.dart';
import 'package:ai_bank_receipt_manager/presentation/screens/save_report_dialog.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/section_header.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reportExportServiceProvider = FutureProvider<ReportExportService>((
  ref,
) async {
  final paths = await ref.watch(appStoragePathsProvider.future);
  final receipts = await ref.watch(receiptRepositoryProvider.future);
  final offices = await ref.watch(officeAccountRepositoryProvider.future);
  final customers = await ref.watch(customerRepositoryProvider.future);
  final dealers = await ref.watch(dealerRepositoryProvider.future);
  return ReportExportService(
    paths: paths,
    query: ReportQueryService(
      receipts: receipts,
      offices: offices,
      customers: customers,
      dealers: dealers,
    ),
  );
});

final reportSaveServiceProvider = FutureProvider<ReportSaveService>((
  ref,
) async {
  final receipts = await ref.watch(receiptRepositoryProvider.future);
  final offices = await ref.watch(officeAccountRepositoryProvider.future);
  final customers = await ref.watch(customerRepositoryProvider.future);
  final dealers = await ref.watch(dealerRepositoryProvider.future);
  return ReportSaveService(
    query: ReportQueryService(
      receipts: receipts,
      offices: offices,
      customers: customers,
      dealers: dealers,
    ),
  );
});

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportKind _kind = ReportKind.dailyReceipt;
  ReportFormat _format = ReportFormat.pdf;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _bankName;
  String? _officeAccountId;
  var _includeImages = false;
  var _busy = false;
  String? _lastPath;
  ReportDocument? _preview;

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedAccountingDateProvider);
    final theme = Theme.of(context);

    return PageScroll(
      children: [
        SectionHeader(
          title: 'Reports',
          subtitle:
              'PDF and Excel exports always read your saved local records. '
              '${BusinessRules.officeEntrySafety} Export never changes entry statuses.',
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report type', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ReportKind>(
                    isExpanded: true,
                    value: _kind,
                    items: [
                      for (final kind in ReportKind.values)
                        DropdownMenuItem(value: kind, child: Text(kind.title)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _kind = value;
                              _preview = null;
                            });
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Format', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<ReportFormat>(
                segments: const [
                  ButtonSegment(
                    value: ReportFormat.pdf,
                    label: Text('PDF'),
                    icon: Icon(Icons.picture_as_pdf_outlined),
                  ),
                  ButtonSegment(
                    value: ReportFormat.xlsx,
                    label: Text('Excel'),
                    icon: Icon(Icons.table_chart_outlined),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() => _format = value.first),
              ),
              const SizedBox(height: 12),
              Text(
                'Selected accounting date: ${formatAccountingDate(selectedDate)}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickFrom(),
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _dateFrom == null
                          ? 'From date'
                          : formatAccountingDate(_dateFrom!),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickTo(),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _dateTo == null
                          ? 'To date'
                          : formatAccountingDate(_dateTo!),
                    ),
                  ),
                  if (_kind == ReportKind.bankWise)
                    SizedBox(
                      width: 180,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Bank name',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(
                          () => _bankName = v.trim().isEmpty ? null : v.trim(),
                        ),
                      ),
                    ),
                  Consumer(
                    builder: (context, ref, _) {
                      final accountsAsync = ref.watch(
                        selectableOfficeAccountsProvider,
                      );
                      return accountsAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (accounts) => SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String?>(
                            // ignore: deprecated_member_use
                            value: _officeAccountId,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Office account',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All offices'),
                              ),
                              for (final a in accounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.displayName),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    _officeAccountId = v;
                                    _preview = null;
                                  }),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include receipt image appendix (PDF)'),
                value: _includeImages && _format == ReportFormat.pdf,
                onChanged: _busy || _format != ReportFormat.pdf
                    ? null
                    : (v) => setState(() => _includeImages = v),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _runPreview(selectedDate),
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview counts'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _saveReport(selectedDate),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save to device'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _export(selectedDate, share: true),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share / WhatsApp'),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_lastPath != null) ...[
                const SizedBox(height: 12),
                Text('Saved: $_lastPath', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_preview!.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(_preview!.subtitle),
                const SizedBox(height: 12),
                Text('Rows: ${_preview!.summary.rowCount}'),
                Text('Pending: ${_preview!.summary.pendingCount}'),
                Text('Entered: ${_preview!.summary.enteredCount}'),
                Text(
                  'Reconciliation: ${_preview!.summary.reconciliationCount}',
                ),
                for (final t in _preview!.summary.totalsByCurrency)
                  Text(
                    '${t.currency}: received ${formatPkr(t.received)} / '
                    'sent ${formatPkr(t.sent)}',
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Export safety: reports regenerate from the current saved desk. '
          'Adding more receipts later includes them on the next export without '
          'resetting Entered ticks.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  ReportCriteria _criteria(DateTime selectedDate) {
    final useDaily =
        _kind == ReportKind.dailyReceipt &&
        _dateFrom == null &&
        _dateTo == null;
    return ReportCriteria(
      kind: _kind,
      accountingDate:
          useDaily ||
              _kind == ReportKind.mutalib ||
              _kind == ReportKind.ad ||
              _kind == ReportKind.pendingEntries ||
              _kind == ReportKind.enteredEntries ||
              _kind == ReportKind.reconciliationRequired
          ? selectedDate
          : null,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      bankName: _bankName,
      mappedAccountId: _officeAccountId,
      includeImageAppendix: _includeImages && _format == ReportFormat.pdf,
    );
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? ref.read(selectedAccountingDateProvider),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dateFrom = picked);
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? ref.read(selectedAccountingDateProvider),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dateTo = picked);
    }
  }

  Future<void> _runPreview(DateTime selectedDate) async {
    setState(() => _busy = true);
    try {
      final service = await ref.read(reportExportServiceProvider.future);
      final doc = await service.preview(_criteria(selectedDate));
      if (!mounted) {
        return;
      }
      setState(() => _preview = doc);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveReport(DateTime selectedDate) async {
    if (_format == ReportFormat.xlsx) {
      await _export(selectedDate, share: false);
      return;
    }

    final mode = await showSaveReportDialog(context);
    if (mode == null || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      final service = await ref.read(reportSaveServiceProvider.future);
      final outcome = await service.save(
        criteria: _criteria(selectedDate),
        mode: mode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = outcome.document;
        _lastPath =
            outcome.pdfPath ??
            (outcome.galleryFileNames.isEmpty
                ? null
                : '${outcome.galleryPagesSaved} Gallery page(s)');
      });
      final messenger = ScaffoldMessenger.of(context);
      if (outcome.pdfCancelled && !outcome.anySucceeded) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Save cancelled. Nothing was written.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(outcome.summaryMessage())),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save the report. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export(DateTime selectedDate, {required bool share}) async {
    setState(() => _busy = true);
    try {
      final service = await ref.read(reportExportServiceProvider.future);
      final result = share
          ? await service.exportAndShare(
              criteria: _criteria(selectedDate),
              format: _format,
            )
          : await service.exportToFile(
              criteria: _criteria(selectedDate),
              format: _format,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPath = result.filePath;
        _preview = result.document;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            share
                ? 'Shared ${result.document.summary.rowCount} receipts'
                : 'Saved ${result.document.summary.rowCount} receipts',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to export the report. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
