import 'package:ai_bank_receipt_manager/application/reports/report_save_service.dart';
import 'package:flutter/material.dart';

Future<ReportSaveMode?> showSaveReportDialog(BuildContext context) {
  return showDialog<ReportSaveMode>(
    context: context,
    builder: (context) => const SaveReportDialog(),
  );
}

class SaveReportDialog extends StatelessWidget {
  const SaveReportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Save Report'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how to save the current filtered report. '
              'Gallery images are rendered from the PDF pages so they match '
              'exactly.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _SaveOption(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Save PDF',
              subtitle: 'Choose folder and file name on this device',
              onTap: () => Navigator.pop(context, ReportSaveMode.pdfOnly),
            ),
            _SaveOption(
              icon: Icons.photo_library_outlined,
              title: 'Save Image to Gallery',
              subtitle: 'One PNG per PDF page in AI Bank Receipt Manager',
              onTap: () => Navigator.pop(context, ReportSaveMode.galleryOnly),
            ),
            _SaveOption(
              icon: Icons.save_alt_outlined,
              title: 'Save PDF + Image',
              subtitle: 'Save PDF to a chosen location and Gallery PNGs',
              onTap: () => Navigator.pop(context, ReportSaveMode.pdfAndGallery),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SaveOption extends StatelessWidget {
  const _SaveOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}
