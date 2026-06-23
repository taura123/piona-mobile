import 'package:flutter/foundation.dart';

@immutable
class BoardingPassOcrFields {
  const BoardingPassOcrFields({
    required this.passengerName,
    required this.pnrOrBarcode,
    required this.flight,
    required this.origin,
    required this.destination,
    required this.boardingDate,
    required this.seat,
    required this.confidence,
  });

  final String? passengerName;
  final String? pnrOrBarcode;
  final String? flight;
  final String? origin;
  final String? destination;
  final String? boardingDate;
  final String? seat;

  /// 0..1 heuristic confidence for extracted essentials.
  final double confidence;
}

class BoardingPassOcrMapper {
  BoardingPassOcrMapper._();

  static BoardingPassOcrFields extractFromTextLines(List<String> lines) {
    final normalized = lines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map(_normalize)
        .toList();

    final name = _extractName(normalized);
    final pnr = _extractPnr(normalized);
    final flight = _extractFlight(normalized);
    final (origin, destination) = _extractAirports(normalized);
    final seat = _extractSeat(normalized);
    final date = _extractDate(normalized);

    final essentials = <Object?>[
      name,
      pnr,
      flight,
      origin,
      destination,
      seat,
      date,
    ];
    final filled = essentials.where((v) {
      if (v is String) return v.trim().isNotEmpty;
      return v != null;
    }).length;
    final confidence = (filled / essentials.length).clamp(0.0, 1.0);

    return BoardingPassOcrFields(
      passengerName: name,
      pnrOrBarcode: pnr,
      flight: flight,
      origin: origin,
      destination: destination,
      boardingDate: date,
      seat: seat,
      confidence: confidence,
    );
  }

  static String _normalize(String s) {
    final upper = s.toUpperCase();
    final noWeird = upper
        .replaceAll(RegExp(r'[\t\r]'), ' ')
        .replaceAll('—', '-')
        .replaceAll('–', '-');
    return noWeird.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _extractName(List<String> lines) {
    for (final l in lines) {
      if (l.contains('/')) {
        final parts = l.split(RegExp(r'\s+'));
        for (final p in parts) {
          if (p.contains('/') && p.length >= 5) {
            // Typical BCBP: LAST/FIRST...
            final cleaned = p.replaceAll(RegExp(r'[^A-Z/]+'), '');
            if (cleaned.contains('/') && cleaned.length >= 5) {
              final nameParts = cleaned.split('/');
              if (nameParts.length >= 2) {
                final last = nameParts[0].trim();
                final first = nameParts[1].trim();
                final merged = '$first $last'.trim();
                if (merged.replaceAll(' ', '').length >= 4) return merged;
              }
            }
          }
        }
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.contains('PASSENGER') || l.contains('NAME')) {
        final next = (i + 1 < lines.length) ? lines[i + 1] : '';
        final candidate = next.replaceAll(RegExp(r'[^A-Z ]+'), ' ').trim();
        if (candidate.replaceAll(' ', '').length >= 4) return candidate;
      }
    }

    return null;
  }

  static String? _extractPnr(List<String> lines) {
    final keyed = <RegExp>[
      RegExp(r'\bPNR\b'),
      RegExp(r'\bBOOKING\b'),
      RegExp(r'\bRESERVATION\b'),
      RegExp(r'\bCODE\b'),
    ];
    for (final l in lines) {
      if (!keyed.any((r) => r.hasMatch(l))) continue;
      final m = RegExp(r'\b([A-Z0-9]{6})\b').firstMatch(l);
      if (m != null) return m.group(1);
    }
    for (final l in lines) {
      final m = RegExp(r'\b([A-Z0-9]{6})\b').firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? _extractFlight(List<String> lines) {
    for (final l in lines) {
      if (l.contains('FLIGHT')) {
        final m = RegExp(r'\b([A-Z0-9]{2,3})\s*([0-9]{1,4})\b').firstMatch(l);
        if (m != null) return '${m.group(1)} ${m.group(2)!.padLeft(4, '0')}';
      }
    }
    for (final l in lines) {
      final m = RegExp(r'\b([A-Z0-9]{2,3})\s*([0-9]{3,4})\b').firstMatch(l);
      if (m != null) return '${m.group(1)} ${m.group(2)!.padLeft(4, '0')}';
    }
    return null;
  }

  static (String?, String?) _extractAirports(List<String> lines) {
    for (final l in lines) {
      if (l.contains('/')) continue; // avoid name-like tokens (DOE/JOHN)

      final fromTo = RegExp(
        r'\bFROM\s+([A-Z]{3})\b.*\bTO\s+([A-Z]{3})\b',
      ).firstMatch(l);
      if (fromTo != null) return (fromTo.group(1), fromTo.group(2));

      final route = RegExp(r'\b([A-Z]{3})\b\s*[-–>]+\s*\b([A-Z]{3})\b')
          .firstMatch(l);
      if (route != null) return (route.group(1), route.group(2));
    }

    final all = <String>[];
    final airportRe = RegExp(r'\b([A-Z]{3})\b');
    for (final l in lines) {
      if (l.contains('/')) continue;
      for (final m in airportRe.allMatches(l)) {
        final code = m.group(1)!;
        if (_isProbablyAirport(code)) all.add(code);
      }
    }
    final uniq = <String>[];
    for (final a in all) {
      if (!uniq.contains(a)) uniq.add(a);
    }
    if (uniq.length >= 2) return (uniq[0], uniq[1]);
    return (uniq.isNotEmpty ? uniq[0] : null, null);
  }

  static bool _isProbablyAirport(String code) {
    const excluded = <String>{
      'THE',
      'AND',
      'FOR',
      'YOU',
      'NOT',
      'AIR',
      'GATE',
      'SEAT',
      'NAME',
      'TOO',
      'FROM',
      'TO',
      'POS',
    };
    return !excluded.contains(code);
  }

  static String? _extractSeat(List<String> lines) {
    for (final l in lines) {
      if (l.contains('SEAT')) {
        final m = RegExp(r'\b([0-9]{1,2}[A-F])\b').firstMatch(l);
        if (m != null) return m.group(1);
      }
    }
    for (final l in lines) {
      final m = RegExp(r'\b([0-9]{1,2}[A-F])\b').firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? _extractDate(List<String> lines) {
    for (final l in lines) {
      final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(l);
      if (iso != null) return '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
    }
    for (final l in lines) {
      final dmy = RegExp(r'\b(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})\b')
          .firstMatch(l);
      if (dmy != null) {
        final dd = dmy.group(1)!.padLeft(2, '0');
        final mm = dmy.group(2)!.padLeft(2, '0');
        final yyRaw = dmy.group(3)!;
        final yyyy = yyRaw.length == 2 ? '20$yyRaw' : yyRaw;
        return '$yyyy-$mm-$dd';
      }
    }
    for (final l in lines) {
      // 16APR / 16APR26 / 16APR2026
      final m = RegExp(r'\b(\d{1,2})([A-Z]{3})(\d{0,4})\b').firstMatch(l);
      if (m != null) {
        final dd = m.group(1)!.padLeft(2, '0');
        final mon = _monthToNumber(m.group(2)!);
        if (mon == null) continue;
        final tail = m.group(3) ?? '';
        final yyyy = switch (tail.length) {
          2 => '20$tail',
          4 => tail,
          _ => DateTime.now().year.toString(),
        };
        return '$yyyy-$mon-$dd';
      }
    }
    return null;
  }

  static String? _monthToNumber(String mon) {
    const m = <String, String>{
      'JAN': '01',
      'FEB': '02',
      'MAR': '03',
      'APR': '04',
      'MAY': '05',
      'JUN': '06',
      'JUL': '07',
      'AUG': '08',
      'SEP': '09',
      'OCT': '10',
      'NOV': '11',
      'DEC': '12',
    };
    return m[mon];
  }
}

