import 'package:flutter_test/flutter_test.dart';

import 'package:piona_mobile/utils/bcbp_parser.dart';

void main() {
  test('julianDateToYMD converts day-of-year to YYYY-MM-DD', () {
    final ref = DateTime(2026, 1, 15);
    expect(julianDateToYMD('001', ref), '2026-01-01');
    expect(julianDateToYMD('032', ref), '2026-02-01');
  });

  test('parseBCBP parses a typical IATA BCBP raw string', () {
    const raw =
        'M1DOE/JOHN            E1234567 CGKDXB GA1234 123 1001Y011A0001 100';
    final parsed = parseBCBP(raw);

    expect(parsed.isSuccess, isTrue, reason: parsed.error ?? 'Unknown error');
    expect(parsed.name, isNotNull);
    expect(parsed.name!.trim(), isNotEmpty);
    expect(parsed.origin ?? parsed.originAirport, anyOf(isNotNull, isNotEmpty));
    expect(parsed.destination ?? parsed.destinationAirport,
        anyOf(isNotNull, isNotEmpty));
  });
}

