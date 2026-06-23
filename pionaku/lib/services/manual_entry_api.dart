import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_errors.dart';
import 'piona_http_client.dart';

class ManualEntryApi {
  ManualEntryApi({PionaHttpClient? httpClient})
      : _http = httpClient ?? PionaHttpClient.instance;

  final PionaHttpClient _http;

  Future<List<Map<String, dynamic>>> listManualEntries({
    required String bearerToken,
    String? date,
    String? status,
    String? airportCode,
  }) async {
    final qp = <String, String>{};
    final d = date?.trim();
    if (d != null && d.isNotEmpty) qp['date'] = d;
    final s = status?.trim();
    if (s != null && s.isNotEmpty) qp['status'] = s;
    final ac = airportCode?.trim();
    if (ac != null && ac.isNotEmpty) qp['airportCode'] = ac;

    final uri = _http.url('/manual-entry', qp.isEmpty ? null : qp);
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const ManualEntryApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ManualEntryApiException(msg ?? 'Gagal memuat manual entry.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ManualEntryApiException('Response manual entry tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const ManualEntryApiException('Daftar manual entry tidak valid.');
    }
    return items
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createManualEntry({
    required String bearerToken,
    required Map<String, Object?> body,
  }) async {
    final uri = _http.url('/manual-entry');
    late final http.Response res;
    try {
      res = await _http.post(
        uri,
        body: jsonEncode(body),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const ManualEntryApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ManualEntryApiException(msg ?? 'Gagal membuat manual entry.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ManualEntryApiException(
          'Response create manual entry tidak valid.');
    }
    final item = decoded['item'];
    if (item is! Map<String, dynamic>) {
      throw const ManualEntryApiException('Data manual entry tidak valid.');
    }
    return item;
  }

  Future<Map<String, dynamic>> updateManualEntry({
    required String bearerToken,
    required String id,
    Map<String, Object?>? body,
  }) async {
    final uri = _http.url('/manual-entry/$id');
    late final http.Response res;
    try {
      res = await _http.put(
        uri,
        body: jsonEncode(body ?? const <String, Object?>{}),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const ManualEntryApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ManualEntryApiException(msg ?? 'Gagal mengupdate manual entry.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ManualEntryApiException(
          'Response update manual entry tidak valid.');
    }
    final item = decoded['item'];
    if (item is! Map<String, dynamic>) {
      throw const ManualEntryApiException('Data manual entry tidak valid.');
    }
    return item;
  }

  Future<void> deleteManualEntry({
    required String bearerToken,
    required String id,
  }) async {
    final uri = _http.url('/manual-entry/$id');
    late final http.Response res;
    try {
      res = await _http.delete(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const ManualEntryApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ManualEntryApiException(msg ?? 'Gagal menghapus manual entry.');
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

class ManualEntryApiException implements Exception {
  const ManualEntryApiException(this.message);

  final String message;

  @override
  String toString() => 'ManualEntryApiException: $message';
}
