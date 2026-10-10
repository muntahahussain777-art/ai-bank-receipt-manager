import 'package:ai_bank_receipt_manager/shared/widgets/notice_panel.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/page_scroll.dart';
import 'package:ai_bank_receipt_manager/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const reports = <_ReportSpec>[
      _ReportSpec(
        title: 'Daily entry list (PDF)',
        body:
            'A printable list for the selected accounting date, meant to be typed into WinForms.',
      ),
      _ReportSpec(
        title: 'Daily entry list (XLSX)',
        body: 'The same daily list as a spreadsheet.',
      ),
      _ReportSpec(
        title: 'Reconciliation worksheet (PDF)',
        body:
            'Old and new financial values for receipts that need a manual correction.',
      ),
    ];
    return PageScroll(
      children: [
        const PreviewBanner(),
        const SizedBox(height: 16),
        Text(
          'Report files are not created in Phase 1.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < reports.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ReportCard(spec: reports[i]),
        ],
      ],
    );
  }
}

class _ReportSpec {
  const _ReportSpec({required this.title, required this.body});

  final String title;
  final String body;
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.spec});

  final _ReportSpec spec;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(spec.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(spec.body),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => showPhaseNotice(
              context,
              title: 'Reports are not exported',
              message: 'Phase 1 does not create a PDF or XLSX file.',
            ),
            child: const Text('Not available in Phase 1'),
          ),
        ],
      ),
    );
  }
}
