import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../services/passenger_scan_store.dart';
import '../utils/passenger_recap.dart';

@immutable
class ReportRow {
  const ReportRow({
    required this.scanDay,
    required this.scannedAtIsoUtc,
    required this.airportCode,
    required this.userDisplay,
    required this.scanPoint,
    required this.source,
    required this.status,
    required this.flight,
    required this.origin,
    required this.destination,
    required this.passengerType,
    required this.category,
    required this.pnrOrCode,
    required this.passengerName,
    required this.seat,
    required this.boardingDate,
    required this.barcodeValue,
  });

  final String scanDay; // YYYY-MM-DD (local, based on scannedAt)
  final String scannedAtIsoUtc;
  final String airportCode; // may be N/A for PassengerScan
  final String userDisplay; // may be N/A for PassengerScan
  final String scanPoint;
  final String source; // scan/manual
  final String status; // complete/partial/failed
  final String flight;
  final String origin;
  final String destination;
  final String passengerType;
  final String category;
  final String pnrOrCode;
  final String passengerName;
  final String seat;
  final String boardingDate;
  final String barcodeValue;
}

String fmtIsoDay(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

List<DateTime> expandCalendarDays(DateTimeRange range) {
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final out = <DateTime>[];
  var cur = start;
  while (!cur.isAfter(end)) {
    out.add(cur);
    cur = cur.add(const Duration(days: 1));
  }
  return out;
}

bool recordMatchesRange(PassengerScanRecord r, DateTimeRange range) {
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  final parsedBoarding = parseBoardingDateString(r.boardingDate);

  bool inRange(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    return (dd.isAtSameMomentAs(start) || dd.isAfter(start)) &&
        (dd.isAtSameMomentAs(end) || dd.isBefore(end));
  }

  final byBoarding = parsedBoarding != null && inRange(parsedBoarding);
  final byScannedAt = inRange(r.scannedAt);
  return byBoarding || byScannedAt;
}

List<PassengerScanRecord> filterRecordsForRange(
  List<PassengerScanRecord> records,
  DateTimeRange range,
) {
  return records
      .where((r) => recordMatchesRange(r, range))
      .toList(growable: false);
}

List<ReportRow> buildReportRows({
  required List<PassengerScanRecord> records,
  required DateTimeRange range,
}) {
  final filtered = filterRecordsForRange(records, range);

  return filtered.map((r) {
    final scanDay = fmtIsoDay(r.scannedAt);
    return ReportRow(
      scanDay: scanDay,
      scannedAtIsoUtc: r.scannedAt.toUtc().toIso8601String(),
      airportCode: r.airportCode.trim().isEmpty ? 'N/A' : r.airportCode.trim(),
      userDisplay: 'N/A',
      scanPoint: r.scanPoint.trim().isEmpty ? 'N/A' : r.scanPoint,
      source: r.source.trim().isEmpty ? 'scan' : r.source,
      status: r.status.name,
      flight: r.flight.trim().isEmpty ? 'N/A' : r.flight,
      origin: r.origin.trim().isEmpty ? 'N/A' : r.origin,
      destination: r.destination.trim().isEmpty ? 'N/A' : r.destination,
      passengerType: r.passengerType.trim().isEmpty ? 'N/A' : r.passengerType,
      category: r.category.trim().isEmpty ? 'N/A' : r.category,
      pnrOrCode: r.pnrOrCode.trim().isEmpty ? 'N/A' : r.pnrOrCode,
      passengerName: r.passengerName.trim().isEmpty ? 'N/A' : r.passengerName,
      seat: r.seat.trim().isEmpty ? 'N/A' : r.seat,
      boardingDate: r.boardingDate.trim().isEmpty ? 'N/A' : r.boardingDate,
      barcodeValue: r.barcodeValue.trim(),
    );
  }).toList(growable: false);
}

@immutable
class PivotRow {
  const PivotRow({required this.dimensions, required this.count});

  final List<String> dimensions;
  final int count;
}

List<PivotRow> pivotCount(
  List<ReportRow> rows,
  List<String> Function(ReportRow r) dims,
) {
  final map = <String, int>{};
  final keyToDims = <String, List<String>>{};
  for (final r in rows) {
    final d = dims(r).map((e) => e.trim().isEmpty ? 'N/A' : e.trim()).toList();
    final key = d.join('|');
    map[key] = (map[key] ?? 0) + 1;
    keyToDims.putIfAbsent(key, () => d);
  }
  final out = map.entries
      .map((e) => PivotRow(dimensions: keyToDims[e.key]!, count: e.value))
      .toList(growable: false);
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}
