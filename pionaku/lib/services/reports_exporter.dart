import 'dart:io';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfGoogleFonts;
import 'package:share_plus/share_plus.dart';

import '../services/passenger_scan_store.dart';
import '../services/reports_dataset.dart';

class ReportsExporter {
  ReportsExporter._();

  static Future<void> sharePdf({
    required DateTimeRange range,
    required List<PassengerScanRecord> scanRecords,
  }) async {
    if (kIsWeb) {
      throw const ReportsExporterException(
        'Export on web is not supported in this build.',
      );
    }

    final rows = buildReportRows(records: scanRecords, range: range);
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final doc = pw.Document(
      title: 'PIONA Reports ${_stampRange(range)}',
      author: 'PIONA',
    );

    final byDay = pivotCount(rows, (r) => [r.scanDay]);
    final byAirport = pivotCount(rows, (r) => [r.airportCode]);
    final byScanPoint = pivotCount(rows, (r) => [r.scanPoint]);
    final byUser = pivotCount(rows, (r) => [r.userDisplay]);
    final bySource = pivotCount(rows, (r) => [r.source]);
    final byStatus = pivotCount(rows, (r) => [r.status]);

    final total = rows.length;
    final uniqueBarcodes = rows
        .map((r) => r.barcodeValue.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    int countWhere(String fieldValue, String Function(ReportRow r) getter) =>
        rows.where((r) => getter(r) == fieldValue).length;

    final scanCount = countWhere('scan', (r) => r.source);
    final manualCount = countWhere('manual', (r) => r.source);

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 44),
          theme: pw.ThemeData.withFont(
            base: baseFont,
            bold: boldFont,
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (context) {
          return [
            _pdfHeader(range),
            pw.SizedBox(height: 16),
            _pdfExecutiveSummary(
              total: total,
              uniqueBarcodes: uniqueBarcodes.length,
              scanCount: scanCount,
              manualCount: manualCount,
              completeCount: countWhere('complete', (r) => r.status),
              partialCount: countWhere('partial', (r) => r.status),
              failedCount: countWhere('failed', (r) => r.status),
            ),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Highlights'),
            pw.SizedBox(height: 10),
            _pdfTwoColumnTables(
              leftTitle: 'Top Airports',
              leftHeaders: const ['Airport', 'Count'],
              leftRows: _takeTop(byAirport, 8),
              rightTitle: 'Top Scan Points',
              rightHeaders: const ['Scan Point', 'Count'],
              rightRows: _takeTop(byScanPoint, 8),
            ),
            pw.SizedBox(height: 14),
            _pdfTwoColumnTables(
              leftTitle: 'Top Users',
              leftHeaders: const ['User', 'Count'],
              leftRows: _takeTop(byUser, 8),
              rightTitle: 'By Source',
              rightHeaders: const ['Source', 'Count'],
              rightRows: _takeTop(bySource, 8),
            ),
            pw.SizedBox(height: 14),
            _pdfTwoColumnTables(
              leftTitle: 'By Status',
              leftHeaders: const ['Status', 'Count'],
              leftRows: _takeTop(byStatus, 8),
              rightTitle: 'Daily Trend',
              rightHeaders: const ['Day', 'Count'],
              rightRows: _takeTop(
                byDay
                  ..sort((a, b) =>
                      a.dimensions.first.compareTo(b.dimensions.first)),
                31,
              ),
            ),
            pw.SizedBox(height: 18),
            _pdfSectionTitle('Appendix: Detail (first 200 rows)'),
            pw.SizedBox(height: 10),
            _pdfDetailTable(rows.take(200).toList(growable: false)),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    final fileName = 'reports_${_stampRange(range)}.pdf';

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            path,
            mimeType: 'application/pdf',
          ),
        ],
        subject: 'PIONA Reports ${_stampRange(range)}',
      ),
    );
  }

  static Future<void> shareXlsx({
    required DateTimeRange range,
    required List<PassengerScanRecord> scanRecords,
  }) async {
    if (kIsWeb) {
      throw const ReportsExporterException(
        'Export on web is not supported in this build.',
      );
    }

    final rows = buildReportRows(records: scanRecords, range: range);
    final fileName = _xlsxFileName(range);

    final excel = xlsx.Excel.createExcel();
    _writeDataSheet(excel, rows);
    _writePivotSheet(
      excel,
      'Summary_ByDay',
      headers: const ['Scan Day', 'Count'],
      pivots: pivotCount(rows, (r) => [r.scanDay]),
    );
    _writePivotSheet(
      excel,
      'Summary_ByAirport',
      headers: const ['Airport', 'Count'],
      pivots: pivotCount(rows, (r) => [r.airportCode]),
    );
    _writePivotSheet(
      excel,
      'Summary_ByScanPoint',
      headers: const ['Scan Point', 'Count'],
      pivots: pivotCount(rows, (r) => [r.scanPoint]),
    );
    _writePivotSheet(
      excel,
      'Summary_ByUser',
      headers: const ['User', 'Count'],
      pivots: pivotCount(rows, (r) => [r.userDisplay]),
    );
    _writePivotSheet(
      excel,
      'Summary_BySource',
      headers: const ['Source', 'Count'],
      pivots: pivotCount(rows, (r) => [r.source]),
    );
    _writePivotSheet(
      excel,
      'Summary_ByStatus',
      headers: const ['Status', 'Count'],
      pivots: pivotCount(rows, (r) => [r.status]),
    );

    final bytes = excel.save(fileName: fileName);
    if (bytes == null || bytes.isEmpty) {
      throw const ReportsExporterException('Could not build Excel file.');
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: 'PIONA Reports ${_stampRange(range)}',
      ),
    );
  }

  static String _xlsxFileName(DateTimeRange range) {
    final stamp = _stampRange(range);
    return 'reports_$stamp.xlsx';
  }

  static String _stampRange(DateTimeRange range) {
    final s = range.start;
    final e = range.end;
    final start =
        '${s.year}${s.month.toString().padLeft(2, '0')}${s.day.toString().padLeft(2, '0')}';
    final end =
        '${e.year}${e.month.toString().padLeft(2, '0')}${e.day.toString().padLeft(2, '0')}';
    return start == end ? start : '${start}_to_$end';
  }

  static void _writeDataSheet(xlsx.Excel excel, List<ReportRow> rows) {
    const name = 'Data';
    final sheet = excel[name];
    final headers = <xlsx.CellValue>[
      xlsx.TextCellValue('Scan Day'),
      xlsx.TextCellValue('Scanned At (UTC)'),
      xlsx.TextCellValue('Airport'),
      xlsx.TextCellValue('User'),
      xlsx.TextCellValue('Scan Point'),
      xlsx.TextCellValue('Source'),
      xlsx.TextCellValue('Status'),
      xlsx.TextCellValue('Flight'),
      xlsx.TextCellValue('Origin'),
      xlsx.TextCellValue('Destination'),
      xlsx.TextCellValue('Passenger Type'),
      xlsx.TextCellValue('Category'),
      xlsx.TextCellValue('PNR/Code'),
      xlsx.TextCellValue('Passenger Name'),
      xlsx.TextCellValue('Seat'),
      xlsx.TextCellValue('Boarding Date'),
      xlsx.TextCellValue('Barcode Value'),
    ];
    sheet.appendRow(headers);
    _styleHeaderRow(sheet, headers.length);

    for (final r in rows) {
      sheet.appendRow([
        xlsx.TextCellValue(r.scanDay),
        xlsx.TextCellValue(r.scannedAtIsoUtc),
        xlsx.TextCellValue(r.airportCode),
        xlsx.TextCellValue(r.userDisplay),
        xlsx.TextCellValue(r.scanPoint),
        xlsx.TextCellValue(r.source),
        xlsx.TextCellValue(r.status),
        xlsx.TextCellValue(r.flight),
        xlsx.TextCellValue(r.origin),
        xlsx.TextCellValue(r.destination),
        xlsx.TextCellValue(r.passengerType),
        xlsx.TextCellValue(r.category),
        xlsx.TextCellValue(r.pnrOrCode),
        xlsx.TextCellValue(r.passengerName),
        xlsx.TextCellValue(r.seat),
        xlsx.TextCellValue(r.boardingDate),
        xlsx.TextCellValue(r.barcodeValue),
      ]);
    }
  }

  static void _writePivotSheet(
    xlsx.Excel excel,
    String name, {
    required List<String> headers,
    required List<PivotRow> pivots,
  }) {
    final sheet = excel[name];
    final headerCells = headers.map(xlsx.TextCellValue.new).toList();
    sheet.appendRow(headerCells);
    _styleHeaderRow(sheet, headers.length);

    for (final p in pivots) {
      final dims = p.dimensions.map(xlsx.TextCellValue.new).toList();
      sheet.appendRow([
        ...dims,
        xlsx.IntCellValue(p.count),
      ]);
    }
  }

  static void _styleHeaderRow(xlsx.Sheet sheet, int colCount) {
    final style = xlsx.CellStyle(
      bold: true,
      fontColorHex: xlsx.ExcelColor.white,
      backgroundColorHex: xlsx.ExcelColor.fromHexString('1F4E79'),
      horizontalAlign: xlsx.HorizontalAlign.Center,
      verticalAlign: xlsx.VerticalAlign.Center,
    );

    for (var c = 0; c < colCount; c += 1) {
      final cell = sheet.cell(xlsx.CellIndex.indexByColumnRow(
        columnIndex: c,
        rowIndex: 0,
      ));
      cell.cellStyle = style;
    }
  }
}

pw.Widget _pdfHeader(DateTimeRange range) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: PdfColors.blue900,
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PIONA Reports',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Date range: ${_fmtPdfDate(range.start)} - ${_fmtPdfDate(range.end)}',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated at: ${_fmtPdfDateTime(DateTime.now())}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        pw.Container(
          width: 10,
          height: 10,
          decoration: const pw.BoxDecoration(
            color: PdfColors.white,
            shape: pw.BoxShape.circle,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _pdfExecutiveSummary({
  required int total,
  required int uniqueBarcodes,
  required int scanCount,
  required int manualCount,
  required int completeCount,
  required int partialCount,
  required int failedCount,
}) {
  pw.Widget card(String title, String value, {PdfColor? color}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: const pw.TextStyle(
                fontSize: 9.5,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: color ?? PdfColors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _pdfSectionTitle('Executive summary'),
      pw.SizedBox(height: 10),
      pw.Row(
        children: [
          card('Total scans', '$total', color: PdfColors.blue800),
          pw.SizedBox(width: 10),
          card('Unique barcodes', '$uniqueBarcodes', color: PdfColors.blue800),
          pw.SizedBox(width: 10),
          card('Scan vs Manual', '$scanCount / $manualCount'),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Row(
        children: [
          card('Complete', '$completeCount', color: PdfColors.green700),
          pw.SizedBox(width: 10),
          card('Partial', '$partialCount', color: PdfColors.orange700),
          pw.SizedBox(width: 10),
          card('Failed', '$failedCount', color: PdfColors.red700),
        ],
      ),
    ],
  );
}

pw.Widget _pdfSectionTitle(String title) {
  return pw.Text(
    title,
    style: pw.TextStyle(
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blueGrey900,
    ),
  );
}

List<List<String>> _takeTop(List<PivotRow> pivots, int n) {
  return pivots.take(n).map((p) {
    final dim = p.dimensions.isEmpty ? 'N/A' : p.dimensions.first;
    return [dim, p.count.toString()];
  }).toList(growable: false);
}

pw.Widget _pdfTwoColumnTables({
  required String leftTitle,
  required List<String> leftHeaders,
  required List<List<String>> leftRows,
  required String rightTitle,
  required List<String> rightHeaders,
  required List<List<String>> rightRows,
}) {
  pw.Widget table(String title, List<String> headers, List<List<String>> rows) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey900,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.symmetric(
                inside: const pw.BorderSide(color: PdfColors.grey200),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _pdfTh(headers[0]),
                    _pdfTh(headers[1], alignRight: true),
                  ],
                ),
                for (var i = 0; i < rows.length; i += 1)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _pdfTd(rows[i][0]),
                      _pdfTd(rows[i][1], alignRight: true),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      table(leftTitle, leftHeaders, leftRows),
      pw.SizedBox(width: 10),
      table(rightTitle, rightHeaders, rightRows),
    ],
  );
}

pw.Widget _pdfTh(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 9.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blueGrey900,
      ),
    ),
  );
}

pw.Widget _pdfTd(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      maxLines: 2,
      style: const pw.TextStyle(
        fontSize: 9.2,
        color: PdfColors.grey800,
      ),
    ),
  );
}

pw.Widget _pdfDetailTable(List<ReportRow> rows) {
  const headers = [
    'Day',
    'Airport',
    'Scan Point',
    'Source',
    'Status',
    'Flight',
    'PNR'
  ];
  return pw.Table(
    border: pw.TableBorder.symmetric(
      inside: const pw.BorderSide(color: PdfColors.grey200),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.2),
      1: pw.FlexColumnWidth(1.0),
      2: pw.FlexColumnWidth(1.5),
      3: pw.FlexColumnWidth(1.0),
      4: pw.FlexColumnWidth(1.0),
      5: pw.FlexColumnWidth(1.0),
      6: pw.FlexColumnWidth(1.3),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: headers.map((h) => _pdfTh(h)).toList(growable: false),
      ),
      for (var i = 0; i < rows.length; i += 1)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : PdfColors.grey50,
          ),
          children: [
            _pdfTd(rows[i].scanDay),
            _pdfTd(rows[i].airportCode),
            _pdfTd(rows[i].scanPoint),
            _pdfTd(rows[i].source),
            _pdfTd(rows[i].status),
            _pdfTd(rows[i].flight),
            _pdfTd(rows[i].pnrOrCode),
          ],
        ),
    ],
  );
}

String _fmtPdfDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = d.year.toString();
  return '$dd/$mm/$yy';
}

String _fmtPdfDateTime(DateTime d) {
  final dd = _fmtPdfDate(d);
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd $hh:$mi';
}

class ReportsExporterException implements Exception {
  const ReportsExporterException(this.message);

  final String message;

  @override
  String toString() => 'ReportsExporterException: $message';
}
