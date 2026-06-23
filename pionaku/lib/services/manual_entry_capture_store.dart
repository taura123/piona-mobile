import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'manual_entry_api.dart';
import 'session_context_store.dart';

/// Scan mode when the photo was taken (matches [ScanMode] without importing scan_screen).
enum ManualCaptureScanSource { normal, transit }

enum ManualEntryCaptureWorkflowStatus {
  pending,
  aiGenerated,
  completed,
  trash,
}

@immutable
class ManualEntryCaptureRecord {
  const ManualEntryCaptureRecord({
    required this.id,
    this.backendId,
    required this.relativePath,
    required this.displayFileName,
    required this.sizeBytes,
    required this.createdAt,
    required this.source,
    required this.status,
    required this.userDisplay,
    required this.scanPoint,
    required this.airportCode,
    this.parsed,
  });

  final int id;
  final String? backendId;
  /// Path under app documents dir, e.g. `manual_entry_captures/images/...`.
  final String relativePath;
  final String displayFileName;
  final int sizeBytes;
  final DateTime createdAt;
  final ManualCaptureScanSource source;
  final ManualEntryCaptureWorkflowStatus status;
  final String userDisplay;
  final String scanPoint;
  final String airportCode;

  /// Parsed/draft passenger fields (may be partial).
  final ManualEntryParsedDraft? parsed;

  ManualEntryCaptureRecord copyWith({
    ManualEntryCaptureWorkflowStatus? status,
    ManualEntryParsedDraft? parsed,
  }) {
    return ManualEntryCaptureRecord(
      id: id,
      relativePath: relativePath,
      displayFileName: displayFileName,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      source: source,
      status: status ?? this.status,
      userDisplay: userDisplay,
      scanPoint: scanPoint,
      airportCode: airportCode,
      parsed: parsed ?? this.parsed,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'backendId': backendId,
        'relativePath': relativePath,
        'displayFileName': displayFileName,
        'sizeBytes': sizeBytes,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'source': source.name,
        'status': status.name,
        'userDisplay': userDisplay,
        'scanPoint': scanPoint,
        'airportCode': airportCode,
        'parsed': parsed?.toJson(),
      };

  static ManualCaptureScanSource _parseSource(String? s) {
    for (final v in ManualCaptureScanSource.values) {
      if (v.name == s) return v;
    }
    return ManualCaptureScanSource.normal;
  }

  static ManualEntryCaptureWorkflowStatus _parseStatus(String? s) {
    for (final v in ManualEntryCaptureWorkflowStatus.values) {
      if (v.name == s) return v;
    }
    return ManualEntryCaptureWorkflowStatus.pending;
  }

  static ManualEntryCaptureRecord fromJson(Map<String, Object?> m) {
    return ManualEntryCaptureRecord(
      id: (m['id'] as num).toInt(),
      backendId: (m['backendId'] as String?)?.trim(),
      relativePath: (m['relativePath'] as String?) ?? '',
      displayFileName: (m['displayFileName'] as String?) ?? '—',
      sizeBytes: (m['sizeBytes'] as num).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['createdAtMs'] as num).toInt(),
      ),
      source: _parseSource(m['source'] as String?),
      status: _parseStatus(m['status'] as String?),
      userDisplay: (m['userDisplay'] as String?)?.trim().isNotEmpty == true
          ? (m['userDisplay'] as String).trim()
          : 'admin',
      scanPoint: (m['scanPoint'] as String?) ?? '',
      airportCode: (m['airportCode'] as String?) ?? '',
      parsed: ManualEntryParsedDraft.fromJson(
        m['parsed'],
      ),
    );
  }

  static ManualEntryCaptureRecord fromBackend({
    required Map<String, dynamic> json,
    required int localId,
    String? relativePath,
    String? displayFileName,
    int? sizeBytes,
  }) {
    final createdAtRaw = (json['createdAt'] as String?) ?? '';
    final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    final sourceRaw = (json['source'] as String?)?.trim().toLowerCase() ?? '';
    final statusRaw = (json['status'] as String?)?.trim().toLowerCase() ?? '';
    return ManualEntryCaptureRecord(
      id: localId,
      backendId: (json['id'] as String?)?.trim(),
      relativePath: relativePath ?? ((json['relativePath'] as String?) ?? ''),
      displayFileName:
          displayFileName ?? ((json['displayFileName'] as String?) ?? '—'),
      sizeBytes: sizeBytes ?? ((json['sizeBytes'] as num?)?.toInt() ?? 0),
      createdAt: createdAt,
      source: sourceRaw == 'transit'
          ? ManualCaptureScanSource.transit
          : ManualCaptureScanSource.normal,
      status: switch (statusRaw) {
        'aigenerated' => ManualEntryCaptureWorkflowStatus.aiGenerated,
        'completed' => ManualEntryCaptureWorkflowStatus.completed,
        'trash' => ManualEntryCaptureWorkflowStatus.trash,
        _ => ManualEntryCaptureWorkflowStatus.pending,
      },
      userDisplay: (json['userDisplay'] as String?)?.trim() ?? '',
      scanPoint: (json['scanPoint'] as String?)?.trim() ?? '',
      airportCode: (json['airportCode'] as String?)?.trim() ?? '',
      parsed: ManualEntryParsedDraft.fromJson(json['parsed']),
    );
  }
}

@immutable
class ManualEntryParsedDraft {
  const ManualEntryParsedDraft({
    required this.barcodeValue,
    required this.passengerName,
    required this.boardingDate,
    required this.seat,
    required this.flight,
    required this.origin,
    required this.destination,
    required this.passengerType,
    required this.category,
    required this.scanPoint,
    this.extractionSource = 'unknown',
    this.extractionConfidence = 0,
  });

  final String barcodeValue;
  final String passengerName;
  final String boardingDate;
  final String seat;
  final String flight;
  final String origin;
  final String destination;
  final String passengerType;
  final String category;
  final String scanPoint;
  /// Where the values primarily came from: `barcode`, `ocr`, or `unknown`.
  final String extractionSource;

  /// 0..1 heuristic confidence for the extracted fields.
  final double extractionConfidence;

  Map<String, Object?> toJson() => {
        'barcodeValue': barcodeValue,
        'passengerName': passengerName,
        'boardingDate': boardingDate,
        'seat': seat,
        'flight': flight,
        'origin': origin,
        'destination': destination,
        'passengerType': passengerType,
        'category': category,
        'scanPoint': scanPoint,
        'extractionSource': extractionSource,
        'extractionConfidence': extractionConfidence,
      };

  static ManualEntryParsedDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    String s(String key) => (m[key] as String?) ?? '';
    double d(String key) {
      final v = m[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? 0;
      return 0;
    }
    return ManualEntryParsedDraft(
      barcodeValue: s('barcodeValue'),
      passengerName: s('passengerName'),
      boardingDate: s('boardingDate'),
      seat: s('seat'),
      flight: s('flight'),
      origin: s('origin'),
      destination: s('destination'),
      passengerType: s('passengerType'),
      category: s('category'),
      scanPoint: s('scanPoint'),
      extractionSource: s('extractionSource'),
      extractionConfidence: d('extractionConfidence'),
    );
  }
}

/// Persists manual camera captures for the Manual Entry list.
class ManualEntryCaptureStore extends ChangeNotifier {
  ManualEntryCaptureStore._();

  static final ManualEntryCaptureStore instance = ManualEntryCaptureStore._();

  final ManualEntryApi _api = ManualEntryApi();
  final SessionContextStore _session = SessionContextStore.instance;
  final List<ManualEntryCaptureRecord> _records = <ManualEntryCaptureRecord>[];
  final Set<int> _pendingDeleteLocalIds = <int>{};
  final Set<String> _deletedBackendIds = <String>{};
  final Set<String> _deletedFingerprints = <String>{};
  int _nextId = 1;
  bool _loaded = false;

  List<ManualEntryCaptureRecord> get records =>
      List<ManualEntryCaptureRecord>.unmodifiable(_records);

  Future<File> _indexFile() async {
    final doc = await getApplicationDocumentsDirectory();
    return File('${doc.path}/manual_entry_captures/index.json');
  }

  Future<void> loadOnce({String? bearerToken, bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final idx = await _indexFile();
      if (!await idx.exists()) {
        _loaded = true;
      } else {
        final raw = jsonDecode(await idx.readAsString());
        if (raw is Map) {
          final delIds = raw['deletedBackendIds'];
          if (delIds is List) {
            _deletedBackendIds
              ..clear()
              ..addAll(delIds.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty));
          }
          final delFp = raw['deletedFingerprints'];
          if (delFp is List) {
            _deletedFingerprints
              ..clear()
              ..addAll(delFp.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty));
          }
          final recs = raw['records'];
          if (recs is List) {
            _records.clear();
            for (final item in recs) {
              if (item is Map) {
                try {
                  _records.add(
                    ManualEntryCaptureRecord.fromJson(
                      item.map((k, v) => MapEntry(k.toString(), v)),
                    ),
                  );
                } catch (_) {}
              }
            }
            _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            var maxId = 0;
            for (final r in _records) {
              if (r.id > maxId) maxId = r.id;
            }
            _nextId = maxId + 1;
          }
        } else if (raw is List) {
          _records.clear();
          for (final item in raw) {
            if (item is Map) {
              try {
                _records.add(
                  ManualEntryCaptureRecord.fromJson(
                    item.map((k, v) => MapEntry(k.toString(), v)),
                  ),
                );
              } catch (_) {}
            }
          }
          _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          var maxId = 0;
          for (final r in _records) {
            if (r.id > maxId) maxId = r.id;
          }
          _nextId = maxId + 1;
        }
      }

      final token = bearerToken?.trim() ?? _session.jwtToken?.trim() ?? '';
      if (token.isNotEmpty) {
        final ac = _session.originCode.trim();
        final items = await _api.listManualEntries(
          bearerToken: token,
          airportCode: ac.isEmpty ? null : ac,
        );
        final byBackendId = <String, ManualEntryCaptureRecord>{};
        for (final r in _records) {
          final bid = r.backendId;
          if (bid != null && bid.isNotEmpty) byBackendId[bid] = r;
        }

        for (final item in items) {
          final bid = (item['id'] as String?)?.trim() ?? '';
          if (bid.isEmpty) continue;
          if (_deletedBackendIds.contains(bid)) {
            continue;
          }
          final createdAtRaw = (item['createdAt'] as String?) ?? '';
          final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
          final fp = '${(item['displayFileName'] as String?) ?? ''}|${createdAt.millisecondsSinceEpoch}';
          if (_deletedFingerprints.contains(fp)) {
            try {
              await _api.deleteManualEntry(bearerToken: token, id: bid);
              _deletedBackendIds.add(bid);
              await _saveIndex();
            } catch (_) {}
            continue;
          }
          final existing = byBackendId[bid];
          final localId = existing?.id ?? _nextId++;
          final merged = ManualEntryCaptureRecord.fromBackend(
            json: item,
            localId: localId,
            relativePath: existing?.relativePath,
            displayFileName: existing?.displayFileName,
            sizeBytes: existing?.sizeBytes,
          );
          final idxLocal = _records.indexWhere((e) => e.backendId == bid);
          if (idxLocal >= 0) {
            _records[idxLocal] = merged;
          } else {
            _records.insert(0, merged);
          }
        }
        _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _saveIndex();
      }
    } catch (e, st) {
      debugPrint('ManualEntryCaptureStore.loadOnce: $e\n$st');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveIndex() async {
    final idx = await _indexFile();
    await idx.parent.create(recursive: true);
    await idx.writeAsString(
      jsonEncode(<String, Object?>{
        'records': _records.map((e) => e.toJson()).toList(growable: false),
        'deletedBackendIds': _deletedBackendIds.toList(growable: false),
        'deletedFingerprints': _deletedFingerprints.toList(growable: false),
      }),
    );
  }

  Future<String> fileAbsolutePath(ManualEntryCaptureRecord r) async {
    final doc = await getApplicationDocumentsDirectory();
    if (r.relativePath.trim().isEmpty) return '';
    return '${doc.path}/${r.relativePath}';
  }

  /// Saves PNG [imageBytes] and appends a pending Manual Entry record.
  Future<ManualEntryCaptureRecord?> addCapture({
    required Uint8List imageBytes,
    required ManualCaptureScanSource source,
    required String userDisplay,
    required String scanPoint,
    required String airportCode,
    ManualEntryParsedDraft? parsed,
  }) async {
    await loadOnce();
    try {
      final doc = await getApplicationDocumentsDirectory();
      final utc = DateTime.now().toUtc();
      final stamp = utc.toIso8601String().replaceAll(':', '-');
      final displayName = 'passenger_photo_$stamp.png';
      final rel = 'manual_entry_captures/images/$displayName';
      final file = File('${doc.path}/$rel');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(imageBytes, flush: true);
      final len = await file.length();
      final id = _nextId++;
      final record = ManualEntryCaptureRecord(
        id: id,
        backendId: null,
        relativePath: rel,
        displayFileName: displayName,
        sizeBytes: len,
        createdAt: DateTime.now(),
        source: source,
        status: ManualEntryCaptureWorkflowStatus.pending,
        userDisplay: userDisplay.trim().isEmpty ? 'admin' : userDisplay.trim(),
        scanPoint: scanPoint.trim(),
        airportCode: airportCode.trim(),
        parsed: parsed,
      );
      _records.insert(0, record);
      await _saveIndex();
      notifyListeners();

      final token = _session.jwtToken?.trim() ?? '';
      if (token.isNotEmpty) {
        final created = await _api.createManualEntry(
          bearerToken: token,
          body: <String, Object?>{
            'relativePath': rel,
            'displayFileName': displayName,
            'sizeBytes': len,
            'createdAt': record.createdAt.toUtc().toIso8601String(),
            'source': source.name,
            'status': record.status.name,
            'userDisplay': record.userDisplay,
            'scanPoint': record.scanPoint,
            'airportCode': record.airportCode,
            if (parsed != null) 'parsed': parsed.toJson(),
          },
        );
        final bid = (created['id'] as String?)?.trim();
        if (bid != null && bid.isNotEmpty) {
          // If user deleted before backendId was set, delete it from DB now
          // even if the local record is already removed.
          if (_pendingDeleteLocalIds.remove(id)) {
            try {
              await _api.deleteManualEntry(bearerToken: token, id: bid);
              _deletedBackendIds.add(bid);
            } catch (_) {}
            await _saveIndex();
            notifyListeners();
            return record;
          }
          final idxLocal = _records.indexWhere((e) => e.id == id);
          if (idxLocal >= 0) {
            final existing = _records[idxLocal];
            _records[idxLocal] = ManualEntryCaptureRecord(
              id: existing.id,
              backendId: bid,
              relativePath: existing.relativePath,
              displayFileName: existing.displayFileName,
              sizeBytes: existing.sizeBytes,
              createdAt: existing.createdAt,
              source: existing.source,
              status: existing.status,
              userDisplay: existing.userDisplay,
              scanPoint: existing.scanPoint,
              airportCode: existing.airportCode,
              parsed: existing.parsed,
            );
            await _saveIndex();
            notifyListeners();
          }
        }
      }
      return record;
    } catch (e, st) {
      debugPrint('ManualEntryCaptureStore.addCapture: $e\n$st');
      return null;
    }
  }

  /// Adds a pending Manual Entry record without an image (e.g. invalid scan).
  Future<ManualEntryCaptureRecord?> addDraft({
    required ManualCaptureScanSource source,
    required String userDisplay,
    required String scanPoint,
    required String airportCode,
    required ManualEntryParsedDraft parsed,
  }) async {
    await loadOnce();
    try {
      final id = _nextId++;
      final utc = DateTime.now().toUtc();
      final stamp = utc.toIso8601String().replaceAll(':', '-');
      final displayName = 'scan_draft_$stamp';
      final record = ManualEntryCaptureRecord(
        id: id,
        backendId: null,
        relativePath: '',
        displayFileName: displayName,
        sizeBytes: 0,
        createdAt: DateTime.now(),
        source: source,
        status: ManualEntryCaptureWorkflowStatus.pending,
        userDisplay: userDisplay.trim().isEmpty ? 'admin' : userDisplay.trim(),
        scanPoint: scanPoint.trim(),
        airportCode: airportCode.trim(),
        parsed: parsed,
      );
      _records.insert(0, record);
      await _saveIndex();
      notifyListeners();

      final token = _session.jwtToken?.trim() ?? '';
      if (token.isNotEmpty) {
        final created = await _api.createManualEntry(
          bearerToken: token,
          body: <String, Object?>{
            'relativePath': '',
            'displayFileName': displayName,
            'sizeBytes': 0,
            'createdAt': record.createdAt.toUtc().toIso8601String(),
            'source': source.name,
            'status': record.status.name,
            'userDisplay': record.userDisplay,
            'scanPoint': record.scanPoint,
            'airportCode': record.airportCode,
            'parsed': parsed.toJson(),
          },
        );
        final bid = (created['id'] as String?)?.trim();
        if (bid != null && bid.isNotEmpty) {
          if (_pendingDeleteLocalIds.remove(id)) {
            try {
              await _api.deleteManualEntry(bearerToken: token, id: bid);
              _deletedBackendIds.add(bid);
            } catch (_) {}
            await _saveIndex();
            notifyListeners();
            return record;
          }
          final idxLocal = _records.indexWhere((e) => e.id == id);
          if (idxLocal >= 0) {
            final existing = _records[idxLocal];
            _records[idxLocal] = ManualEntryCaptureRecord(
              id: existing.id,
              backendId: bid,
              relativePath: existing.relativePath,
              displayFileName: existing.displayFileName,
              sizeBytes: existing.sizeBytes,
              createdAt: existing.createdAt,
              source: existing.source,
              status: existing.status,
              userDisplay: existing.userDisplay,
              scanPoint: existing.scanPoint,
              airportCode: existing.airportCode,
              parsed: existing.parsed,
            );
            await _saveIndex();
            notifyListeners();
          }
        }
      }
      return record;
    } catch (e, st) {
      debugPrint('ManualEntryCaptureStore.addDraft: $e\n$st');
      return null;
    }
  }

  Future<void> updateById(int id, ManualEntryCaptureRecord updated) async {
    await loadOnce();
    final index = _records.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _records[index] = updated;
    await _saveIndex();
    notifyListeners();

    final bid = updated.backendId?.trim() ?? '';
    final token = _session.jwtToken?.trim() ?? '';
    if (bid.isNotEmpty && token.isNotEmpty) {
      final body = <String, Object?>{};
      body['status'] = updated.status.name;
      if (updated.parsed != null) body['parsed'] = updated.parsed!.toJson();
      try {
        await _api.updateManualEntry(bearerToken: token, id: bid, body: body);
      } catch (_) {}
    }
  }

  Future<void> deleteById(int id) async {
    await loadOnce();
    final index = _records.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final rec = _records[index];
    try {
      final doc = await getApplicationDocumentsDirectory();
      final f = File('${doc.path}/${rec.relativePath}');
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    _records.removeWhere((e) => e.id == id);
    await _saveIndex();
    notifyListeners();

    final bid = rec.backendId?.trim() ?? '';
    final token = _session.jwtToken?.trim() ?? '';
    if (bid.isNotEmpty && token.isNotEmpty) {
      try {
        await _api.deleteManualEntry(bearerToken: token, id: bid);
        _deletedBackendIds.add(bid);
        await _saveIndex();
      } catch (_) {}
      return;
    }

    // Deleted locally before backendId was known; delete later once created.
    if (bid.isEmpty) {
      _pendingDeleteLocalIds.add(id);
      final fp = '${rec.displayFileName}|${rec.createdAt.millisecondsSinceEpoch}';
      _deletedFingerprints.add(fp);
      await _saveIndex();
    }
  }
}
