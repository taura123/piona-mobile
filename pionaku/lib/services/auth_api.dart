import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_errors.dart';
import 'piona_http_client.dart';

class AuthApi {
  AuthApi({PionaHttpClient? httpClient})
      : _http = httpClient ?? PionaHttpClient.instance;

  final PionaHttpClient _http;

  Future<LoginResponse> login({
    required String username,
    required String password,
    required String airportCode,
    required String checkpoint,
  }) async {
    final uri = _http.url('/auth/login');
    late final http.Response res;
    try {
      res = await _http.post(
        uri,
        body: jsonEncode({
          'username': username,
          'password': password,
          'airportCode': airportCode,
          'checkpoint': checkpoint,
        }),
        bearerToken: null,
      );
    } on ApiTimeoutException {
      throw const AuthException('Gagal login. Cek koneksi dan coba lagi.');
    }

    if (res.statusCode == 401) {
      throw const AuthException('Username atau password salah.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw AuthException(msg ?? 'Gagal login. Coba lagi.');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AuthException('Response login tidak valid.');
    }

    final token = decoded['token'];
    final user = decoded['user'];
    if (token is! String || token.trim().isEmpty) {
      throw const AuthException('Token login tidak ditemukan.');
    }
    if (user is! Map<String, dynamic>) {
      throw const AuthException('User login tidak valid.');
    }

    final userId = user['id'];
    final usernameOut = user['username'];
    final roleOut = user['role'];
    final userIdOut = userId is String
        ? userId.trim()
        : userId is num
            ? userId.toInt().toString()
            : '';
    if (userIdOut.isEmpty) {
      throw const AuthException('User ID tidak ditemukan.');
    }
    if (usernameOut is! String || usernameOut.trim().isEmpty) {
      throw const AuthException('Username tidak ditemukan.');
    }
    if (roleOut is! String || roleOut.trim().isEmpty) {
      throw const AuthException('Role user tidak ditemukan.');
    }

    return LoginResponse(
      token: token,
      userId: userIdOut,
      username: usernameOut,
      role: roleOut,
    );
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

class LoginResponse {
  const LoginResponse({
    required this.token,
    required this.userId,
    required this.username,
    required this.role,
  });

  final String token;
  final String userId;
  final String username;
  final String role;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
