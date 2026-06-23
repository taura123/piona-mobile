import 'dart:async';

import 'package:flutter/foundation.dart';

import '../screens/scan_screen.dart';
import 'api_errors.dart';
import 'passenger_scans_api.dart';
import 'session_context_store.dart';

@immutable
class PassengerScanRecord {
  const PassengerScanRecord({
    required this.id,
    required this.passengerName,
    required this.boardingDate,
    required this.seat,
    required this.flight,
    required this.origin,
    required this.destination,
    required this.passengerType,
    required this.category,
    required this.pnrOrCode,
    required this.airportCode,
    required this.scanPoint,
    required this.scannedAt,
    required this.status,
    required this.barcodeValue,
    required this.source,
  });

  final int id;
  final String passengerName;
  final String boardingDate;
  final String seat;
  final String flight;
  final String origin;
  final String destination;
  final String passengerType;
  final String category;
  final String pnrOrCode;
  final String airportCode;
  final String scanPoint;
  final DateTime scannedAt;
  final ParseStatus status;
  final String barcodeValue;
  final String source;
}

class PassengerScanStore extends ChangeNotifier {
  PassengerScanStore._();

  static final PassengerScanStore instance = PassengerScanStore._();

  final PassengerScansApi _api = PassengerScansApi();
  final SessionContextStore _session = SessionContextStore.instance;
  final List<PassengerScanRecord> _records = <PassengerScanRecord>[];
  final Set<String> _dedupeKeys = <String>{};
  final Set<String> _scanDayDedupeKeys = <String>{};
  int _nextId = 1;
  DateTime _lastRefreshedAt = DateTime.now();
  bool _syncing = false;
  final Map<int, _PendingPost> _pendingPosts = <int, _PendingPost>{};
  final List<int> _pendingOrder = <int>[];
  bool _posting = false;
  Timer? _retryTimer;
  String? _lastPostErrorMessage;
  DateTime? _lastPostFailedAt;

  List<PassengerScanRecord> get records =>
      List<PassengerScanRecord>.unmodifiable(_records);

  DateTime get lastRefreshedAt => _lastRefreshedAt;

  bool get isSyncing => _syncing;

  int get pendingSyncCount => _pendingPosts.length;

  String? get lastPostErrorMessage => _lastPostErrorMessage;

  DateTime? get lastPostFailedAt => _lastPostFailedAt;

  String? consumeLastPostErrorMessage() {
    final msg = _lastPostErrorMessage;
    if (msg == null) return null;
    _lastPostErrorMessage = null;
    _lastPostFailedAt = null;
    notifyListeners();
    return msg;
  }

  bool _dedupedWarning = false;

  bool get didDedupedWarning => _dedupedWarning;

  bool consumeDedupedWarning() {
    if (!_dedupedWarning) return false;
    _dedupedWarning = false;
    return true;
  }

  void refreshTick() {
    _lastRefreshedAt = DateTime.now();
    notifyListeners();
  }

  static String _scanDayUtc(DateTime d) {
    final utc = d.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _scanDedupeKey({
    required String barcodeValue,
    required String scanPoint,
    required DateTime scannedAt,
  }) {
    return '${barcodeValue.trim()}|${scanPoint.trim().toLowerCase()}|${_scanDayUtc(scannedAt)}';
  }

  PassengerScanRecord _fromBackend(Map<String, dynamic> json) {
    final scannedAtRaw = (json['scannedAt'] as String?) ?? '';
    final scannedAt = DateTime.tryParse(scannedAtRaw) ?? DateTime.now();
    final statusRaw = (json['status'] as String?)?.trim().toLowerCase() ?? '';
    final status = switch (statusRaw) {
      'partial' => ParseStatus.partial,
      'failed' => ParseStatus.failed,
      _ => ParseStatus.complete,
    };
    final airportCode = (json['airportCode'] as String?)?.trim() ?? '';
    return PassengerScanRecord(
      id: 0,
      passengerName: (json['passengerName'] as String?)?.trim() ?? 'N/A',
      boardingDate: (json['boardingDate'] as String?)?.trim() ?? 'N/A',
      seat: (json['seat'] as String?)?.trim() ?? 'N/A',
      flight: (json['flight'] as String?)?.trim() ?? 'N/A',
      origin: (json['origin'] as String?)?.trim() ?? 'N/A',
      destination: (json['destination'] as String?)?.trim() ?? 'N/A',
      passengerType: (json['passengerType'] as String?)?.trim() ?? 'N/A',
      category: (json['category'] as String?)?.trim() ?? 'N/A',
      pnrOrCode: (json['pnrOrCode'] as String?)?.trim() ?? 'N/A',
      airportCode: airportCode,
      scanPoint: (json['scanPoint'] as String?)?.trim() ?? 'N/A',
      scannedAt: scannedAt,
      status: status,
      barcodeValue: (json['barcodeValue'] as String?)?.trim() ?? '',
      source: (json['source'] as String?)?.trim() ?? 'scan',
    );
  }

  Future<void> loadFromBackend({
    String? date,
    String? airportCode,
    List<String>? airportCodes,
    String? scanPoint,
    DateTime? since,
    bool replace = false,
  }) async {
    final token = _session.jwtToken?.trim();
    if (token == null || token.isEmpty) return;

    _syncing = true;
    notifyListeners();
    try {
      final items = await _api.listPassengerScans(
        bearerToken: token,
        date: date,
        airportCode: airportCode,
        airportCodes: airportCodes,
        scanPoint: scanPoint,
        since: since,
      );
      final parsed = items.map(_fromBackend).toList(growable: false);
      parsed.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));

      if (replace) {
        _records.clear();
        _dedupeKeys.clear();
        _scanDayDedupeKeys.clear();

        for (final r in parsed) {
          // For source='scan', show only one record per (barcode, scanPoint, scanDay).
          if (r.source == 'scan') {
            final dayKey = _scanDedupeKey(
              barcodeValue: r.barcodeValue,
              scanPoint: r.scanPoint,
              scannedAt: r.scannedAt,
            );
            if (_scanDayDedupeKeys.contains(dayKey)) {
              continue;
            }
            _scanDayDedupeKeys.add(dayKey);
          }
          final key = '${r.barcodeValue}|${r.scannedAt.millisecondsSinceEpoch}';
          _dedupeKeys.add(key);
          _records.add(r);
        }
      } else {
        for (final r in parsed) {
          // For source='scan', avoid duplicates in UI across refreshes.
          if (r.source == 'scan') {
            final dayKey = _scanDedupeKey(
              barcodeValue: r.barcodeValue,
              scanPoint: r.scanPoint,
              scannedAt: r.scannedAt,
            );
            if (_scanDayDedupeKeys.contains(dayKey)) {
              continue;
            }
            _scanDayDedupeKeys.add(dayKey);
          }

          final key = '${r.barcodeValue}|${r.scannedAt.millisecondsSinceEpoch}';
          if (_dedupeKeys.add(key)) {
            _records.insert(0, r);
          }
        }
      }
      _lastRefreshedAt = DateTime.now();
    } on UnauthorizedException {
      _session.clearSession();
      _lastPostErrorMessage = 'Sesi login sudah berakhir. Silakan login ulang.';
      _lastPostFailedAt = DateTime.now();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  static Duration _retryDelay(int attempts) {
    final secs = switch (attempts) {
      <= 0 => 2,
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 16,
      5 => 32,
      _ => 60,
    };
    return Duration(seconds: secs);
  }

  void _armRetryTimer(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _drainPostQueue();
    });
  }

  void _enqueuePost(PassengerScanRecord record) {
    final token = _session.jwtToken?.trim();
    if (token == null || token.isEmpty) {
      _lastPostErrorMessage = 'Belum ada sesi login untuk sinkronisasi scan.';
      _lastPostFailedAt = DateTime.now();
      notifyListeners();
      return;
    }
    if (_pendingPosts.containsKey(record.id)) return;
    _pendingPosts[record.id] = _PendingPost(record);
    _pendingOrder.add(record.id);
    notifyListeners();
    _drainPostQueue();
  }

  Future<void> _drainPostQueue() async {
    if (_posting) return;
    _posting = true;
    try {
      while (_pendingOrder.isNotEmpty) {
        final id = _pendingOrder.first;
        final pending = _pendingPosts[id];
        if (pending == null) {
          _pendingOrder.removeAt(0);
          continue;
        }

        final now = DateTime.now();
        if (pending.nextAttemptAt.isAfter(now)) {
          _armRetryTimer(pending.nextAttemptAt.difference(now));
          break;
        }

        final outcome = await _tryPostToBackend(pending.record);
        if (outcome == _PostOutcome.success ||
            outcome == _PostOutcome.deduped) {
          _pendingPosts.remove(id);
          _pendingOrder.removeAt(0);
          notifyListeners();
          continue;
        }

        pending.attempts += 1;
        final delay = _retryDelay(pending.attempts);
        pending.nextAttemptAt = DateTime.now().add(delay);
        _armRetryTimer(delay);
        break;
      }
    } finally {
      _posting = false;
    }
  }

  Future<_PostOutcome> _tryPostToBackend(PassengerScanRecord record) async {
    final token = _session.jwtToken?.trim();
    if (token == null || token.isEmpty) {
      _lastPostErrorMessage = 'Sesi login sudah berakhir. Silakan login ulang.';
      _lastPostFailedAt = DateTime.now();
      notifyListeners();
      return _PostOutcome.failed;
    }

    final body = <String, Object?>{
      'passengerName': record.passengerName,
      'boardingDate': record.boardingDate,
      'seat': record.seat,
      'flight': record.flight,
      'origin': record.origin,
      'destination': record.destination,
      'passengerType': record.passengerType,
      'category': record.category,
      'pnrOrCode': record.pnrOrCode,
      'airportCode': record.airportCode.trim(),
      'scanPoint': record.scanPoint,
      'scannedAt': record.scannedAt.toUtc().toIso8601String(),
      'status': record.status.name,
      'barcodeValue': record.barcodeValue,
      'source': record.source,
    };

    try {
      final res = await _api.createPassengerScan(bearerToken: token, body: body);
      if (res.deduped) {
        // If backend deduped a scan, rollback the optimistic UI insert.
        if (record.source == 'scan') {
          final idx = _records.indexWhere((r) => r.id == record.id);
          if (idx >= 0) {
            _records.removeAt(idx);
          }
          // Keep the day-level dedupe key present so the next scan won't re-add.
          _scanDayDedupeKeys.add(
            _scanDedupeKey(
              barcodeValue: record.barcodeValue,
              scanPoint: record.scanPoint,
              scannedAt: record.scannedAt,
            ),
          );
        }
        _dedupedWarning = true;
        notifyListeners();
        return _PostOutcome.deduped;
      }
      return _PostOutcome.success;
    } on UnauthorizedException {
      _session.clearSession();
      _lastPostErrorMessage = 'Sesi login sudah berakhir. Silakan login ulang.';
      _lastPostFailedAt = DateTime.now();
      notifyListeners();
      return _PostOutcome.failed;
    } catch (e) {
      _lastPostErrorMessage = 'Gagal sinkronisasi scan: ${e.toString()}';
      _lastPostFailedAt = DateTime.now();
      notifyListeners();
      return _PostOutcome.failed;
    }
  }

  void addFromScan({
    required ScanResultDisplay result,
    required ScanMode mode,
    required String scanPointFallback,
  }) {
    final barcodeValue = result.barcodeValue.trim();
    final scannedAt = result.scannedAt;
    final key = '$barcodeValue|${scannedAt.millisecondsSinceEpoch}';
    if (!_dedupeKeys.add(key)) return;

    final gate = result.gate.trim();
    final scanPoint =
        (gate.isEmpty || gate == 'N/A') ? scanPointFallback : gate;

    final dayKey = _scanDedupeKey(
      barcodeValue: barcodeValue,
      scanPoint: scanPoint,
      scannedAt: scannedAt,
    );
    if (_scanDayDedupeKeys.contains(dayKey)) {
      _dedupedWarning = true;
      notifyListeners();
      return;
    }

    final category = mode == ScanMode.transit ? 'Transit' : 'Normal';

    final record = PassengerScanRecord(
      id: _nextId++,
      passengerName: result.passengerName.trim().isEmpty
          ? 'N/A'
          : result.passengerName.trim(),
      boardingDate: result.boardingDate.trim().isEmpty
          ? 'N/A'
          : result.boardingDate.trim(),
      seat: result.seat.trim().isEmpty ? 'N/A' : result.seat.trim(),
      flight: result.airlineCode.trim().isEmpty
          ? 'N/A'
          : result.airlineCode.trim(),
      origin: result.origin.trim().isEmpty ? 'N/A' : result.origin.trim(),
      destination:
          result.destination.trim().isEmpty ? 'N/A' : result.destination.trim(),
      passengerType: result.criteria.trim().isEmpty
          ? 'N/A'
          : result.criteria.trim(),
      category: category,
      pnrOrCode: barcodeValue.isEmpty ? 'N/A' : barcodeValue,
      airportCode: _session.originCode.trim(),
      scanPoint: scanPoint,
      scannedAt: scannedAt,
      status: result.status,
      barcodeValue: barcodeValue,
      source: 'scan',
    );

    _records.insert(0, record);
    _scanDayDedupeKeys.add(dayKey);
    notifyListeners();
    _enqueuePost(record);
  }

  void addFromManualEntry({
    required String passengerName,
    required String boardingDate,
    required String seat,
    required String flight,
    required String origin,
    required String destination,
    required String passengerType,
    required String category,
    required String barcodeValue,
    required String airportCode,
    required String scanPoint,
    required DateTime scannedAt,
  }) {
    final barcode = barcodeValue.trim();
    final key = '$barcode|${scannedAt.millisecondsSinceEpoch}';
    if (!_dedupeKeys.add(key)) return;

    final record = PassengerScanRecord(
      id: _nextId++,
      passengerName: passengerName.trim().isEmpty ? 'N/A' : passengerName.trim(),
      boardingDate: boardingDate.trim().isEmpty ? 'N/A' : boardingDate.trim(),
      seat: seat.trim().isEmpty ? 'N/A' : seat.trim(),
      flight: flight.trim().isEmpty ? 'N/A' : flight.trim(),
      origin: origin.trim().isEmpty ? 'N/A' : origin.trim(),
      destination: destination.trim().isEmpty ? 'N/A' : destination.trim(),
      passengerType:
          passengerType.trim().isEmpty ? 'N/A' : passengerType.trim(),
      category: category.trim().isEmpty ? 'N/A' : category.trim(),
      pnrOrCode: barcode.isEmpty ? 'N/A' : barcode,
      airportCode: airportCode.trim(),
      scanPoint: scanPoint.trim().isEmpty ? 'N/A' : scanPoint.trim(),
      scannedAt: scannedAt,
      status: ParseStatus.complete,
      barcodeValue: barcode,
      source: 'manual',
    );

    _records.insert(0, record);
    notifyListeners();
    _enqueuePost(record);
  }
}

enum _PostOutcome { success, deduped, failed }

class _PendingPost {
  _PendingPost(this.record)
      : attempts = 0,
        nextAttemptAt = DateTime.now();

  final PassengerScanRecord record;
  int attempts;
  DateTime nextAttemptAt;
}
