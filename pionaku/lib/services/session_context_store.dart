import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds airport / checkpoint chosen at login for use across the app
/// (e.g. Manual Entry Origin & Scan Point). Replace with API/database-backed
/// session when backend is ready.
class SessionContextStore extends ChangeNotifier {
  SessionContextStore._();

  static final SessionContextStore instance = SessionContextStore._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const String _kOriginCodeKey = 'piona.originCode';
  static const String _kAirportOptionLineKey = 'piona.airportOptionLine';
  static const String _kScanPointKey = 'piona.scanPoint';
  static const String _kDisplayUserIdKey = 'piona.displayUserId';
  static const String _kRoleKey = 'piona.role';
  static const String _kJwtTokenKey = 'piona.jwtToken';
  static const String _kAllAirportsKey = 'piona.allAirports';

  /// IATA-style code shown in Manual Entry "Origin" (readonly).
  String _originCode = 'SRG';

  /// Full airport line from login, e.g. `YIA - Yogyakarta International Airport`.
  String _airportOptionLine = 'SRG - Jenderal Ahmad Yani Airport';

  /// Checkpoint / scan point label from login (readonly in Manual Entry).
  String _scanPoint = 'Concordia';

  /// Shown on Manual Entry capture cards (login ID / username).
  String _displayUserId = 'admin';

  /// Backend role for the currently logged in user (e.g. Admin, IT, Scan, View).
  String _role = 'Admin';

  /// JWT token from backend (for API calls). Keep in-memory for now.
  /// (Persist later with secure storage if needed.)
  String? _jwtToken;

  /// Global scope toggle: when true, show data across all airports.
  bool _allAirports = false;

  Timer? _heartbeatTimer;

  String get originCode => _originCode;

  String get airportOptionLine => _airportOptionLine;

  /// Parsed airport name from [airportOptionLine], e.g. `Yogyakarta International Airport`.
  String get airportName {
    final line = _airportOptionLine.trim();
    if (line.isEmpty) return '';
    final idx = line.indexOf(' - ');
    if (idx < 0) return '';
    return line.substring(idx + 3).trim();
  }

  String get scanPoint => _scanPoint;

  String get displayUserId => _displayUserId;

  String get role => _role;

  bool get isAdmin => _role.trim().toLowerCase() == 'admin';

  bool get isIt => _role.trim().toLowerCase() == 'it';

  bool get canManageUsers => isAdmin || isIt;

  String? get jwtToken => _jwtToken;

  bool get allAirports => _allAirports;

  void setAllAirports(bool value) {
    if (_allAirports == value) return;
    _allAirports = value;
    notifyListeners();
    unawaited(_secureStorage.write(
      key: _kAllAirportsKey,
      value: value ? '1' : '0',
    ));
  }

  bool get isLoggedIn {
    final t = _jwtToken?.trim();
    return t != null && t.isNotEmpty;
  }

  Future<void> restoreFromSecureStorage() async {
    try {
      final originCode =
          (await _secureStorage.read(key: _kOriginCodeKey))?.trim();
      final airportOptionLine =
          (await _secureStorage.read(key: _kAirportOptionLineKey))?.trim();
      final scanPoint = (await _secureStorage.read(key: _kScanPointKey))?.trim();
      final displayUserId =
          (await _secureStorage.read(key: _kDisplayUserIdKey))?.trim();
      final role = (await _secureStorage.read(key: _kRoleKey))?.trim();
      final allAirportsRaw =
          (await _secureStorage.read(key: _kAllAirportsKey))?.trim();

      if (originCode != null && originCode.isNotEmpty) {
        _originCode = originCode;
      }
      if (airportOptionLine != null && airportOptionLine.isNotEmpty) {
        _airportOptionLine = airportOptionLine;
      }
      if (scanPoint != null && scanPoint.isNotEmpty) {
        _scanPoint = scanPoint;
      }
      if (displayUserId != null && displayUserId.isNotEmpty) {
        _displayUserId = displayUserId;
      }
      if (role != null && role.isNotEmpty) {
        _role = role;
      }
      _allAirports = allAirportsRaw == '1';
      // IMPORTANT: For this app, we intentionally do NOT restore JWT.
      // User must login every time the app is opened.
      _jwtToken = null;
      notifyListeners();
    } catch (_) {
      // If secure storage is unavailable, ignore and fall back to login.
    }
  }

  Future<void> persistToSecureStorage() async {
    try {
      await _secureStorage.write(key: _kOriginCodeKey, value: _originCode);
      await _secureStorage.write(
          key: _kAirportOptionLineKey, value: _airportOptionLine);
      await _secureStorage.write(key: _kScanPointKey, value: _scanPoint);
      await _secureStorage.write(key: _kDisplayUserIdKey, value: _displayUserId);
      await _secureStorage.write(key: _kRoleKey, value: _role);
      await _secureStorage.write(
          key: _kAllAirportsKey, value: _allAirports ? '1' : '0');
      // IMPORTANT: Never persist JWT to secure storage.
    } catch (_) {
      // Best-effort: ignore persistence errors.
    }
  }

  Future<void> clearPersistedSession() async {
    try {
      await _secureStorage.delete(key: _kOriginCodeKey);
      await _secureStorage.delete(key: _kAirportOptionLineKey);
      await _secureStorage.delete(key: _kScanPointKey);
      await _secureStorage.delete(key: _kDisplayUserIdKey);
      await _secureStorage.delete(key: _kRoleKey);
      await _secureStorage.delete(key: _kAllAirportsKey);
      await _secureStorage.delete(key: _kJwtTokenKey);
    } catch (_) {
      // Best-effort: ignore delete errors.
    }
  }

  void startHeartbeat({
    required Future<void> Function(String bearerToken) ping,
    Duration interval = const Duration(seconds: 30),
  }) {
    _heartbeatTimer?.cancel();
    final t = _jwtToken?.trim();
    if (t == null || t.isEmpty) return;
    _heartbeatTimer = Timer.periodic(interval, (_) async {
      final token = _jwtToken?.trim();
      if (token == null || token.isEmpty) return;
      try {
        await ping(token);
      } catch (_) {
        // Best-effort: ignore ping failure; status will recover next tick.
      }
    });
  }

  /// Parses airport dropdown lines like `YIA - Yogyakarta International Airport`.
  static String airportCodeFromOption(String airportOptionLine) {
    final line = airportOptionLine.trim();
    if (line.isEmpty) return '';
    final idx = line.indexOf(' - ');
    if (idx <= 0) return line;
    return line.substring(0, idx).trim();
  }

  /// Call after successful login with the same values the user selected.
  void setFromLogin({
    required String airportOptionLine,
    required String checkpoint,
    String? displayUserId,
    String? role,
    String? jwtToken,
  }) {
    final normalizedAirportLine = airportOptionLine.trim();
    final code = airportCodeFromOption(normalizedAirportLine);
    final cp = checkpoint.trim();
    if (code.isNotEmpty) {
      _originCode = code;
    }
    if (normalizedAirportLine.isNotEmpty) {
      _airportOptionLine = normalizedAirportLine;
    }
    if (cp.isNotEmpty) {
      _scanPoint = cp;
    }
    final u = displayUserId?.trim();
    if (u != null && u.isNotEmpty) {
      _displayUserId = u;
    }
    final r = role?.trim();
    if (r != null && r.isNotEmpty) {
      final normalized = switch (r.toLowerCase()) {
        'officer' => 'Scan',
        'scanner' => 'Scan',
        'viewer' => 'View',
        _ => r,
      };
      _role = normalized;
    }
    final t = jwtToken?.trim();
    if (t != null && t.isNotEmpty) {
      _jwtToken = t;
    }
    notifyListeners();
    unawaited(persistToSecureStorage());
  }

  void clearSession() {
    _jwtToken = null;
    _allAirports = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    notifyListeners();
    unawaited(clearPersistedSession());
  }
}
