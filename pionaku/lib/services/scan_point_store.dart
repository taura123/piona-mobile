import 'package:flutter/foundation.dart';

import 'scan_points_api.dart';

enum ScanPointStatus {
  active,
  inactive,
}

@immutable
class ScanPointRecord {
  const ScanPointRecord({
    required this.id,
    required this.name,
    required this.status,
    required this.updatedAt,
    required this.activeSessions,
  });

  final String id;
  final String name;
  final ScanPointStatus status;
  final DateTime updatedAt;
  final int activeSessions;

  ScanPointRecord copyWith({
    String? id,
    String? name,
    ScanPointStatus? status,
    DateTime? updatedAt,
    int? activeSessions,
  }) {
    return ScanPointRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      activeSessions: activeSessions ?? this.activeSessions,
    );
  }

  static ScanPointRecord fromBackend(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = switch (rawId) {
      final String v => v.trim(),
      final num v => v.toString(),
      _ => '',
    };
    final name = (json['name'] as String?)?.trim() ?? '';
    final statusRaw = (json['status'] as String?)?.trim().toLowerCase() ?? '';
    final status = statusRaw == 'inactive' ? ScanPointStatus.inactive : ScanPointStatus.active;
    final updatedAtRaw =
        (json['updatedAt'] as String?) ?? (json['createdAt'] as String?) ?? '';
    final updatedAt = DateTime.tryParse(updatedAtRaw) ?? DateTime.now();
    final activeSessions = (json['activeSessions'] as num?)?.toInt() ?? 0;

    return ScanPointRecord(
      id: id,
      name: name,
      status: status,
      updatedAt: updatedAt,
      activeSessions: activeSessions,
    );
  }
}

class ScanPointStore extends ChangeNotifier {
  ScanPointStore._();

  static final ScanPointStore instance = ScanPointStore._();
  final ScanPointsApi _api = ScanPointsApi();

  bool _loaded = false;
  bool _loading = false;
  final List<ScanPointRecord> _records = <ScanPointRecord>[];

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  List<ScanPointRecord> get records =>
      List<ScanPointRecord>.unmodifiable(_records);

  Future<void> loadOnce({String? bearerToken, bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force) return;
    _loading = true;
    notifyListeners();
    try {
      final token = bearerToken?.trim();
      if (token == null || token.isEmpty) {
        // No token: keep existing list (LoginScreen should use public endpoint).
        _records.clear();
        _loaded = true;
        return;
      }

      final items = await _api.listScanPoints(bearerToken: token);
      final parsed = items.map(ScanPointRecord.fromBackend).toList();
      parsed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _records
        ..clear()
        ..addAll(parsed);
      _loaded = true;
    } catch (_) {
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> add({
    required String name,
    required String bearerToken,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final created = await _api.createScanPoint(
      bearerToken: bearerToken,
      name: trimmed,
    );

    _records.insert(0, ScanPointRecord.fromBackend(created));
    notifyListeners();
  }

  Future<void> update({
    required String id,
    required String name,
    required String bearerToken,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;

    final updated = await _api.updateScanPoint(
      bearerToken: bearerToken,
      id: id,
      name: trimmed,
    );

    _records[idx] = ScanPointRecord.fromBackend(updated);
    _records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }

  Future<void> remove({required String id, required String bearerToken}) async {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;

    await _api.deleteScanPoint(bearerToken: bearerToken, id: id);
    _records.removeAt(idx);
    notifyListeners();
  }
}
