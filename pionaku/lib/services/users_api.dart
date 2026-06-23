import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_errors.dart';
import 'piona_http_client.dart';

class MeUser {
  const MeUser({
    required this.id,
    required this.username,
    required this.role,
  });

  final String id;
  final String username;
  final String role;
}

class UsersApi {
  UsersApi({PionaHttpClient? httpClient})
      : _http = httpClient ?? PionaHttpClient.instance;

  final PionaHttpClient _http;

  Future<MeUser> fetchMe({required String bearerToken}) async {
    final uri = _http.url('/me');
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const UsersApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw UsersApiException(msg ?? 'Gagal memuat profil.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const UsersApiException('Response /me tidak valid.');
    }
    final user = decoded['user'];
    if (user is! Map<String, dynamic>) {
      throw const UsersApiException('Data user tidak valid.');
    }
    final id = user['id'];
    final username = user['username'];
    final role = user['role'];
    final idStr = switch (id) {
      final String v => v.trim(),
      final num v => v.toString(),
      _ => '',
    };
    if (idStr.isEmpty) throw const UsersApiException('User ID tidak valid.');
    if (username is! String || username.trim().isEmpty) {
      throw const UsersApiException('Username tidak valid.');
    }
    if (role is! String || role.trim().isEmpty) {
      throw const UsersApiException('Role tidak valid.');
    }
    return MeUser(id: idStr, username: username, role: role);
  }

  Future<List<Map<String, dynamic>>> listUsers({
    required String bearerToken,
  }) async {
    final uri = _http.url('/users');
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const UsersApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw UsersApiException(msg ?? 'Gagal memuat daftar user.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const UsersApiException('Response users tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const UsersApiException('Daftar users tidak valid.');
    }
    return items
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createUser({
    required String bearerToken,
    required String username,
    required String password,
    required String role,
    required String status,
  }) async {
    final uri = _http.url('/users');
    late final http.Response res;
    try {
      res = await _http.post(
        uri,
        body: jsonEncode({
          'username': username,
          'password': password,
          'role': role,
          'status': status,
        }),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const UsersApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw UsersApiException(msg ?? 'Gagal membuat user.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const UsersApiException('Response create user tidak valid.');
    }
    final item = decoded['item'];
    if (item is! Map<String, dynamic>) {
      throw const UsersApiException('Data user tidak valid.');
    }
    return item;
  }

  Future<Map<String, dynamic>> updateUser({
    required String bearerToken,
    required String id,
    String? username,
    String? password,
    String? role,
    String? status,
  }) async {
    final uri = _http.url('/users/$id');
    final body = <String, dynamic>{};
    if (username != null && username.trim().isNotEmpty) {
      body['username'] = username.trim();
    }
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    if (role != null && role.trim().isNotEmpty) {
      body['role'] = role.trim();
    }
    if (status != null && status.trim().isNotEmpty) {
      body['status'] = status.trim();
    }
    late final http.Response res;
    try {
      res = await _http.put(
        uri,
        body: jsonEncode(body),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const UsersApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw UsersApiException(msg ?? 'Gagal mengupdate user.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const UsersApiException('Response update user tidak valid.');
    }
    final item = decoded['item'];
    if (item is! Map<String, dynamic>) {
      throw const UsersApiException('Data user tidak valid.');
    }
    return item;
  }

  Future<void> deleteUser({
    required String bearerToken,
    required String id,
  }) async {
    final uri = _http.url('/users/$id');
    late final http.Response res;
    try {
      res = await _http.delete(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const UsersApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw UsersApiException(msg ?? 'Gagal menghapus user.');
    }
  }

  static String? _tryExtractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final m = decoded['message'];
        if (m is String && m.trim().isNotEmpty) return m.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class UsersApiException implements Exception {
  const UsersApiException(this.message);

  final String message;

  @override
  String toString() => 'UsersApiException: $message';
}
