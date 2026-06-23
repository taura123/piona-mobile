import 'package:flutter/foundation.dart';

/// Parser BCBP (Bar Coded Boarding Pass) berdasarkan standar IATA.
/// Port dari implementasi web PIONA ke Dart untuk aplikasi mobile.

/// Hasil parsing BCBP. Jika [error] non-null, parsing gagal.
class BcbpParsed {
  const BcbpParsed({
    required this.rawData,
    this.error,
    this.name,
    this.pnr,
    this.origin,
    this.destination,
    this.flightNumber,
    this.flightDate,
    this.seatNumber,
    this.sequenceNumber,
    this.type,
    this.airlineCode,
    this.passengerName,
    this.originAirport,
    this.destinationAirport,
    this.checkInDate,
    this.cabinClass,
    this.boardingTime,
    this.passengerStatus,
  });

  final String rawData;
  final String? error;

  final String? name;
  final String? pnr;
  final String? origin;
  final String? destination;
  final String? flightNumber;
  final String? flightDate;
  final String? seatNumber;
  final String? sequenceNumber;
  final String? type;
  final String? airlineCode;
  final String? passengerName;
  final String? originAirport;
  final String? destinationAirport;
  final String? checkInDate;
  final String? cabinClass;
  final String? boardingTime;
  final String? passengerStatus;

  bool get isSuccess => error == null;
}

const String _na = 'N/A';

/// Mengonversi tanggal Julian (3 digit, day-of-year 1-366) ke string YYYY-MM-DD.
/// [julianDayStr] harus 3 digit. [year] opsional; bila null pakai tahun dari [referenceDate].
String julianDateToYMD(
  String julianDayStr,
  DateTime referenceDate, {
  int? year,
}) {
  final dayOfYear = int.tryParse(julianDayStr.trim());
  if (dayOfYear == null || dayOfYear < 1 || dayOfYear > 366) {
    return _na;
  }
  final y = year ?? referenceDate.year;
  final date = DateTime(y, 1, 1).add(Duration(days: dayOfYear - 1));
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Mem-parse string barcode BCBP (IATA) menjadi [BcbpParsed].
/// Posisi field mengikuti standar IATA BCBP.
BcbpParsed parseBCBP(String rawData) {
  try {
    final data = rawData.trim().toUpperCase().padRight(60, ' ');
    if (data.length < 20) {
      return BcbpParsed(rawData: rawData, error: 'BCBP data is too short.');
    }

    // Nama: posisi 2-22 (setelah format code)
    final nameRaw = data.substring(2, 22).trim();
    final nameParts = nameRaw.split('/');
    final name = nameParts.length > 1
        ? '${nameParts[1]} ${nameParts[0]}'.trim()
        : nameRaw;

    if (name.isEmpty) {
      return BcbpParsed(
        rawData: rawData,
        error: 'Failed to parse passenger name from BCBP.',
      );
    }

    // PNR: posisi standar 23-29 (6 karakter)
    String pnr = '';
    if (data.length >= 29) {
      pnr = data.substring(23, 29).trim();
    } else if (data.length >= 25) {
      pnr = data.substring(20, 25).trim();
    }

    // Origin & destination: posisi standar
    String origin = '';
    String destination = '';
    if (data.length >= 36) {
      origin = data.substring(30, 33).trim();
      destination = data.substring(33, 36).trim();
    } else if (data.length >= 28) {
      final airportPattern = RegExp(r'[A-Z]{3}');
      final airports = airportPattern.allMatches(data).map((m) => m.group(0)!).toList();
      if (airports.length >= 2) {
        origin = airports[0];
        destination = airports[1];
      }
    }

    // Nomor penerbangan: beberapa pola
    String flightNumber = '';
    if (data.length >= 36) {
      final flightSection = data.substring(36).trim();
      final patterns = [
        RegExp(r'^([A-Z0-9]{2,3})\s*(\d{3,4})'),
        RegExp(r'^([A-Z0-9]{2,3})(\d{3,4})'),
        RegExp(r'^([A-Z0-9]{2,3})\s*(\d{1,4})'),
        RegExp(r'^([A-Z0-9]{2,3})(\d{1,4})'),
      ];
      for (final pattern in patterns) {
        final match = pattern.firstMatch(flightSection);
        if (match != null) {
          final airlineCode = match.group(1)!;
          final flightDigits = match.group(2)!.padLeft(4, '0');
          flightNumber = '$airlineCode $flightDigits';
          break;
        }
      }
      if (flightNumber.isEmpty) {
        final flightNumberRaw = data.length >= 42
            ? data.substring(36, 42).trim()
            : data.substring(36).trim();
        final fallbackPattern = RegExp(r'^([A-Z0-9]{2,3})(.+)');
        final fallbackMatch = fallbackPattern.firstMatch(flightNumberRaw);
        if (fallbackMatch != null) {
          final airlineCode = fallbackMatch.group(1)!;
          final remaining = fallbackMatch.group(2)!.trim();
          final digitMatch = RegExp(r'\d{3,4}').firstMatch(remaining);
          if (digitMatch != null) {
            final paddedDigits = digitMatch.group(0)!.padLeft(4, '0');
            flightNumber = '$airlineCode $paddedDigits';
          }
        }
      }
    }

    // Tanggal penerbangan (Julian 3 digit, posisi 44-47)
    String flightDate = _na;
    if (data.length >= 47) {
      final julianDateStr = data.substring(44, 47).trim();
      if (julianDateStr.length == 3) {
        flightDate = julianDateToYMD(
          julianDateStr,
          DateTime.now(),
        );
        if (flightDate == _na) flightDate = 'N/A';
      }
    }

    // Seat & sequence: posisi standar
    String seatNumber = '';
    String sequenceNumber = '';
    if (data.length >= 57) {
      seatNumber = data.substring(48, 52).trim();
      sequenceNumber = data.substring(52, 57).trim();
    } else if (data.length >= 52) {
      seatNumber = data.substring(48, 52).trim();
    }

    // Tipe penumpang
    String type = 'Adult';
    if (seatNumber.contains('INF') ||
        seatNumber.contains('NS') ||
        (int.tryParse(seatNumber) == 0)) {
      type = 'Infant';
    }
    if (type == 'Infant') {
      seatNumber = 'INF';
    } else if (seatNumber.isNotEmpty && int.tryParse(seatNumber) != null) {
      seatNumber = seatNumber.replaceFirst(RegExp(r'^0+'), '');
    }

    final airlineCodeVal = flightNumber.isNotEmpty && flightNumber != _na
        ? flightNumber.split(' ')[0]
        : _na;
    final cabinClass = data.length >= 48 ? data.substring(47, 48).trim() : _na;
    final boardingTime = data.length >= 48 ? data.substring(45, 48).trim() : _na;
    final passengerStatus = data.length >= 47 ? data.substring(46, 47).trim() : _na;

    return BcbpParsed(
      rawData: rawData,
      name: name,
      pnr: pnr.isEmpty ? _na : pnr,
      origin: origin.isEmpty ? _na : origin,
      destination: destination.isEmpty ? _na : destination,
      flightNumber: flightNumber.isEmpty ? _na : flightNumber,
      flightDate: flightDate,
      seatNumber: seatNumber.isEmpty ? _na : seatNumber,
      sequenceNumber: sequenceNumber.isEmpty ? _na : sequenceNumber,
      type: type,
      airlineCode: airlineCodeVal,
      passengerName: name,
      originAirport: origin.isEmpty ? _na : origin,
      destinationAirport: destination.isEmpty ? _na : destination,
      checkInDate: flightDate,
      cabinClass: cabinClass.isEmpty ? _na : cabinClass,
      boardingTime: boardingTime.isEmpty ? _na : boardingTime,
      passengerStatus: passengerStatus.isEmpty ? _na : passengerStatus,
    );
  } catch (e, st) {
    debugPrint('Error parsing BCBP: $e');
    debugPrint('$st');
    return BcbpParsed(
      rawData: rawData,
      error: e is Exception ? e.toString() : e.toString(),
    );
  }
}
