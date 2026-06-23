import '../services/passenger_scan_store.dart';

/// One recap row per (flight, origin, destination) for a filtered calendar day.
class PassengerRecapRow {
  const PassengerRecapRow({
    required this.flight,
    required this.flightDateDisplay,
    required this.origin,
    required this.destination,
    required this.adults,
    required this.infants,
    required this.transit,
    required this.total,
  });

  final String flight;
  final String flightDateDisplay;
  final String origin;
  final String destination;
  final int adults;
  final int infants;
  final int transit;
  final int total;
}

bool sameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Formats [d] as dd-MM-yyyy (matches recap table mockup).
String formatRecapFlightDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = d.year.toString();
  return '$dd-$mm-$yy';
}

DateTime? parseBoardingDateString(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == 'N/A' || s == '—' || s == '-') {
    return null;
  }

  final dmy = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$')
      .firstMatch(s);
  if (dmy != null) {
    final day = int.tryParse(dmy.group(1)!);
    final month = int.tryParse(dmy.group(2)!);
    final year = int.tryParse(dmy.group(3)!);
    if (day != null && month != null && year != null) {
      if (month >= 1 &&
          month <= 12 &&
          day >= 1 &&
          day <= 31 &&
          year >= 1900) {
        try {
          return DateTime(year, month, day);
        } catch (_) {
          return null;
        }
      }
    }
  }

  final ymd =
      RegExp(r'^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})$').firstMatch(s);
  if (ymd != null) {
    final year = int.tryParse(ymd.group(1)!);
    final month = int.tryParse(ymd.group(2)!);
    final day = int.tryParse(ymd.group(3)!);
    if (day != null && month != null && year != null) {
      try {
        return DateTime(year, month, day);
      } catch (_) {
        return null;
      }
    }
  }

  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

bool recordMatchesFilterDate(PassengerScanRecord r, DateTime filterDate) {
  final parsed = parseBoardingDateString(r.boardingDate);
  final byBoarding = parsed != null && sameCalendarDay(parsed, filterDate);
  final byScannedAt = sameCalendarDay(r.scannedAt, filterDate);
  return byBoarding || byScannedAt;
}

bool _isInfantType(String passengerType) {
  return passengerType.trim().toLowerCase().contains('inf');
}

/// Groups [records] that fall on [filterDate] into recap rows.
List<PassengerRecapRow> buildPassengerRecapRows(
  List<PassengerScanRecord> records,
  DateTime filterDate,
) {
  final filtered =
      records.where((r) => recordMatchesFilterDate(r, filterDate)).toList();
  if (filtered.isEmpty) {
    return const [];
  }

  final flightDateDisplay = formatRecapFlightDate(filterDate);
  final keyToIndices = <String, List<PassengerScanRecord>>{};

  for (final r in filtered) {
    final flight = r.flight.trim().isEmpty ? 'N/A' : r.flight.trim();
    final origin = r.origin.trim().isEmpty ? 'N/A' : r.origin.trim();
    final dest =
        r.destination.trim().isEmpty ? 'N/A' : r.destination.trim();
    final key = '$flight|$origin|$dest';
    keyToIndices.putIfAbsent(key, () => <PassengerScanRecord>[]).add(r);
  }

  final keys = keyToIndices.keys.toList()..sort();
  final out = <PassengerRecapRow>[];

  for (final key in keys) {
    final list = keyToIndices[key]!;
    final first = list.first;
    final flight = first.flight.trim().isEmpty ? 'N/A' : first.flight.trim();
    final origin = first.origin.trim().isEmpty ? 'N/A' : first.origin.trim();
    final destination =
        first.destination.trim().isEmpty ? 'N/A' : first.destination.trim();

    var adults = 0;
    var infants = 0;
    var transit = 0;
    for (final r in list) {
      if (_isInfantType(r.passengerType)) {
        infants += 1;
      } else {
        adults += 1;
      }
      if (r.category == 'Transit') {
        transit += 1;
      }
    }

    out.add(
      PassengerRecapRow(
        flight: flight,
        flightDateDisplay: flightDateDisplay,
        origin: origin,
        destination: destination,
        adults: adults,
        infants: infants,
        transit: transit,
        total: list.length,
      ),
    );
  }

  return out;
}
