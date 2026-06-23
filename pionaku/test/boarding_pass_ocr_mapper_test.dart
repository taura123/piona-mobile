import 'package:flutter_test/flutter_test.dart';
import 'package:piona_mobile/utils/boarding_pass_ocr_mapper.dart';

void main() {
  group('BoardingPassOcrMapper', () {
    test('extracts core fields from typical boarding pass text', () {
      final lines = <String>[
        'BOARDING PASS',
        'NAME DOE/JOHN',
        'PNR ABC123',
        'FLIGHT GA 402',
        'FROM CGK TO DPS',
        'DATE 16APR2026',
        'SEAT 12A',
      ];

      final r = BoardingPassOcrMapper.extractFromTextLines(lines);
      expect(r.passengerName, 'JOHN DOE');
      expect(r.pnrOrBarcode, 'ABC123');
      expect(r.flight, 'GA 0402');
      expect(r.origin, 'CGK');
      expect(r.destination, 'DPS');
      expect(r.boardingDate, '2026-04-16');
      expect(r.seat, '12A');
      expect(r.confidence, 1);
    });

    test('handles date dd/mm/yy and flight compact format', () {
      final lines = <String>[
        'PASSENGER',
        'JANE SMITH',
        'BOOKING CODE ZX9K2L',
        'JT123',
        'SUB - CGK',
        'DATE 16/04/26',
        'SEAT 3C',
      ];

      final r = BoardingPassOcrMapper.extractFromTextLines(lines);
      expect(r.passengerName, 'JANE SMITH');
      expect(r.pnrOrBarcode, 'ZX9K2L');
      expect(r.flight, 'JT 0123');
      expect(r.boardingDate, '2026-04-16');
      expect(r.seat, '3C');
      expect(r.confidence, greaterThanOrEqualTo(0.7));
    });

    test('returns low confidence when essentials are missing', () {
      final lines = <String>[
        'WELCOME',
        'THANK YOU',
      ];

      final r = BoardingPassOcrMapper.extractFromTextLines(lines);
      expect(r.confidence, 0);
      expect(r.passengerName, isNull);
      expect(r.pnrOrBarcode, isNull);
    });

    test('extracts route from hyphenated airports line', () {
      final lines = <String>[
        'DOE/JOHN',
        'CGK-DPS',
        'GA402',
        '16APR',
        '12A',
      ];

      final r = BoardingPassOcrMapper.extractFromTextLines(lines);
      expect(r.origin, 'CGK');
      expect(r.destination, 'DPS');
      expect(r.flight, 'GA 0402');
      expect(r.seat, '12A');
      expect(r.boardingDate, isNotNull);
    });
  });
}

