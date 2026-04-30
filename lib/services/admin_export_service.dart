import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Admin Export Service (B3) — CSV and PDF exports for admin lists.
///
/// CSV: writes to a temp file and opens the native share sheet so admin
/// can email/Drive/AirDrop the file. Mobile-first.
///
/// PDF: builds a printable doc and uses `printing` package to preview/save.
/// Useful for KPI snapshots / financial summaries shareable with investors.
class AdminExportService {
  AdminExportService._();
  static final instance = AdminExportService._();

  /// Generate a CSV from a list of headers + row maps and share via sheet.
  /// On web, returns the bytes (caller uses `download_helper` shim).
  Future<void> exportCsv({
    required String filename,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? subject,
  }) async {
    final all = <List<dynamic>>[headers, ...rows];
    final csv = const ListToCsvConverter(fieldDelimiter: ',').convert(all);

    if (kIsWeb) {
      // Web export not wired here — caller can use a download_helper.
      debugPrint('[AdminExportService] CSV web fallback not wired: $filename');
      return;
    }

    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: subject ?? filename,
    );
  }

  /// Build a simple A4 PDF with a title + table from headers + rows.
  Future<void> exportPdfTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? subtitle,
    String? filename,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            if (subtitle != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(subtitle,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ],
            pw.SizedBox(height: 12),
            pw.Divider(),
          ],
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${ctx.pageNumber}/${ctx.pagesCount} — Bora App',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
            cellPadding: const pw.EdgeInsets.all(6),
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await _sharePdf(bytes, filename ?? '${_slug(title)}.pdf', title);
  }

  Future<void> _sharePdf(Uint8List bytes, String filename, String title) async {
    if (kIsWeb) {
      // Use `printing.layoutPdf` which opens a print dialog on web.
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_slug(filename)}');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: title,
    );
  }

  String _slug(String s) => s.replaceAll(RegExp(r'[^\w.\-]'), '_');
}
