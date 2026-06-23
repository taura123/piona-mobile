import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'users_api.dart';

enum UserRole {
  admin,
  it,
  scan,
  view,
}

enum UserStatus {
  active,
  inactive,
}

@immutable
class UserRecord {
  const UserRecord({
    required this.id,
    required this.username,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.lastLoginAt,
    this.password,
  });

  final String id;
  final String username;
  final UserRole role;
  final UserStatus status;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  /// Optional; stored locally for management only (not for production auth).
  final String? password;

  UserRecord copyWith({
    String? username,
    UserRole? role,
    UserStatus? status,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? password,
    bool clearPassword = false,
  }) {
    return UserRecord(
      id: id,
      username: username ?? this.username,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      password: clearPassword ? null : (password ?? this.password),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'username': username,
      'role': role.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      if (password != null && password!.isNotEmpty) 'password': password,
    };
  }

  static UserRecord fromJson(Map<String, Object?> json) {
    final roleRaw = ((json['role'] as String?) ?? '').trim().toLowerCase();
    final role = switch (roleRaw) {
      'admin' => UserRole.admin,
      'it' => UserRole.it,
      'scan' || 'scanner' => UserRole.scan,
      'view' || 'viewer' => UserRole.view,
      // Backward compat for older local roles.
      'officer' => UserRole.scan,
      _ => UserRole.scan,
    };
    final statusRaw = (json['status'] as String?) ?? UserStatus.active.name;
    final status = UserStatus.values.firstWhere(
      (s) => s.name == statusRaw,
      orElse: () => UserStatus.active,
    );

    final createdAtRaw = (json['createdAt'] as String?) ?? '';
    final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    final lastLoginAtRaw = (json['lastLoginAt'] as String?) ?? '';
    final lastLoginAt = DateTime.tryParse(lastLoginAtRaw);

    final pwd = json['password'] as String?;

    return UserRecord(
      id: (json['id'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      role: role,
      status: status,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      password: (pwd != null && pwd.isNotEmpty) ? pwd : null,
    );
  }

  static UserRecord fromBackendUser(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = switch (rawId) {
      final String v => v.trim(),
      final num v => v.toString(),
      _ => '',
    };
    final username = (json['username'] as String?)?.trim() ?? '';
    final roleRaw = ((json['role'] as String?) ?? '').trim().toLowerCase();
    final role = switch (roleRaw) {
      'admin' => UserRole.admin,
      'it' => UserRole.it,
      'scan' || 'scanner' => UserRole.scan,
      'view' || 'viewer' => UserRole.view,
      'officer' => UserRole.scan,
      _ => UserRole.scan,
    };
    final createdAtRaw = (json['createdAt'] as String?) ?? '';
    final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    final statusRaw = ((json['status'] as String?) ?? '').trim().toLowerCase();
    final status = switch (statusRaw) {
      'inactive' => UserStatus.inactive,
      _ => UserStatus.active,
    };
    final lastLoginAtRaw = (json['lastLoginAt'] as String?) ?? '';
    final lastLoginAt = DateTime.tryParse(lastLoginAtRaw);

    return UserRecord(
      id: id,
      username: username,
      role: role,
      status: status,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      password: null,
    );
  }
}

class UserStore extends ChangeNotifier {
  UserStore._();

  static final UserStore instance = UserStore._();

  static const String _fileName = 'users.json';

  final UsersApi _usersApi = UsersApi();

  bool _loaded = false;
  bool _loading = false;
  final List<UserRecord> _records = <UserRecord>[];

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  List<UserRecord> get records => List<UserRecord>.unmodifiable(_records);

  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> loadOnce({String? bearerToken, bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force) return;

    _loading = true;
    notifyListeners();
    try {
      final token = bearerToken?.trim();
      if (token != null && token.isNotEmpty) {
        final remote = await _usersApi.listUsers(bearerToken: token);
        final parsed = remote.map(UserRecord.fromBackendUser).toList();
        parsed.sort((a, b) => a.username.compareTo(b.username));
        _records
          ..clear()
          ..addAll(parsed);
        await _saveToFile();
        _loaded = true;
        return;
      }

      final file = await _dataFile();
      if (!await file.exists()) {
        _records
          ..clear()
          ..addAll(_defaultRecords());
        await _saveToFile();
        _loaded = true;
        return;
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _records
          ..clear()
          ..addAll(_defaultRecords());
        await _saveToFile();
        _loaded = true;
        return;
      }

      final parsed = <UserRecord>[];
      for (final item in decoded) {
        if (item is Map) {
          parsed.add(
            UserRecord.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      }

      parsed.sort((a, b) => a.username.compareTo(b.username));
      _records
        ..clear()
        ..addAll(parsed);
      _loaded = true;
    } catch (_) {
      _records
        ..clear()
        ..addAll(_defaultRecords());
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> add({
    required String username,
    required UserRole role,
    required UserStatus status,
    String? password,
    required String bearerToken,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;

    final pwd = password?.trim();
    if (pwd == null || pwd.isEmpty) {
      throw const UsersApiException('Password is required.');
    }
    if (pwd.length < 6) {
      throw const UsersApiException('Password must be at least 6 characters.');
    }

    final apiRole = switch (role) {
      UserRole.admin => 'Admin',
      UserRole.it => 'IT',
      UserRole.scan => 'Scan',
      UserRole.view => 'View',
    };

    final created = await _usersApi.createUser(
      bearerToken: bearerToken,
      username: trimmed,
      password: pwd,
      role: apiRole,
      status: status.name,
    );

    final record = UserRecord.fromBackendUser(created).copyWith(
      clearPassword: true,
    );

    _records.add(record);
    _records.sort((a, b) => a.username.compareTo(b.username));
    await _saveToFile();
    notifyListeners();
  }

  Future<void> update({
    required String id,
    required String username,
    required UserRole role,
    required UserStatus status,
    required String bearerToken,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;

    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;

    final apiRole = switch (role) {
      UserRole.admin => 'Admin',
      UserRole.it => 'IT',
      UserRole.scan => 'Scan',
      UserRole.view => 'View',
    };

    final updated = await _usersApi.updateUser(
      bearerToken: bearerToken,
      id: id,
      username: trimmed,
      role: apiRole,
      status: status.name,
    );

    _records[idx] = UserRecord.fromBackendUser(updated).copyWith(
      password: _records[idx].password,
    );
    _records.sort((a, b) => a.username.compareTo(b.username));
    await _saveToFile();
    notifyListeners();
  }

  Future<void> remove({
    required String id,
    required String bearerToken,
  }) async {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx < 0) return;

    await _usersApi.deleteUser(bearerToken: bearerToken, id: id);
    _records.removeAt(idx);
    await _saveToFile();
    notifyListeners();
  }

  Future<void> _saveToFile() async {
    final file = await _dataFile();
    final payload = _records.map((r) => r.toJson()).toList(growable: false);
    await file.writeAsString(jsonEncode(payload));
  }

  List<UserRecord> _defaultRecords() {
    final now = DateTime.now();
    return const <(String, UserRole)>[
      ('admin', UserRole.admin),
      ('it', UserRole.it),
      ('scan', UserRole.scan),
      ('view', UserRole.view),
    ].map((t) {
      final (u, role) = t;
      return UserRecord(
        id: 'default-${u.toLowerCase()}',
        username: u,
        role: role,
        status: UserStatus.active,
        createdAt: now,
        lastLoginAt: now,
        password: null,
      );
    }).toList(growable: false);
  }
}

