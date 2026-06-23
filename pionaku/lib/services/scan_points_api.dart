import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_errors.dart';
import 'piona_http_client.dart';

class ScanPointsApi {
  ScanPointsApi({PionaHttpClient? httpClient})
      : _http = httpClient ?? PionaHttpClient.instance;

  final PionaHttpClient _http;

  Future<List<Map<String, dynamic>>> listPublicScanPoints() async {
    final uri = _http.url('/public/scan-points');
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: null);
    } on ApiTimeoutException {
      throw const ScanPointsApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const ScanPointsApiException('Gagal memuat scan point.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ScanPointsApiException('Response scan point tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const ScanPointsApiException('Daftar scan point tidak valid.');
    }
    return items
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listScanPoints({
    required String bearerToken,
  }) async {
    final uri = _http.url('/scan-points');
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const ScanPointsApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const ScanPointsApiException('Gagal memuat scan point.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ScanPointsApiException('Response scan point tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const ScanPointsApiException('Daftar scan point tidak valid.');
    }
    return items
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createScanPoint({
    required String bearerToken,
    required String name,
  }) async {
    final uri = _http.url('/scan-points');
    late final http.Response res;
    try {
      res = await _http.post(
        uri,
        body: jsonEncode({'name': name}),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const ScanPointsApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ScanPointsApiException(msg ?? 'Gagal membuat scan point.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ScanPointsApiException('Response create scan point tidak valid.');
    }
    final item = decoded['item'];
    if (item is! Map<String, dynamic>) {
      throw const ScanPointsApiException('Data scan point tidak valid.');
    }
    return item;
  }

  Future<Map<String, dynamic>> updateScanPoint({
    required String bearerToken,
    required String id,
    required String name,
  }) async {
    final uri = _http.url('/scan-points/$id');
    late final http.Response res;
    try {
      res = await _http.put(
        uri,
        body: jsonEncode({'name': name}),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const ScanPointsApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ScanPointsApiException(msg ?? 'Gagal mengupdate scan point.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ScanPointsApiException('Response update scan point tidak valid.');
    }
    final item = decoded['item'];
    if (item is! Map<String, dynamic>) {
      throw const ScanPointsApiException('Data scan point tidak valid.');
    }
    return item;
  }

  Future<void> deleteScanPoint({
    required String bearerToken,
    required String id,
  }) async {
    final uri = _http.url('/scan-points/$id');
    late final http.Response res;
    try {
      res = await _http.delete(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const ScanPointsApiException('Permintaan habis waktu.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw ScanPointsApiException(msg ?? 'Gagal menghapus scan point.');
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

class ScanPointsApiException implements Exception {
  const ScanPointsApiException(this.message);

  final String message;

  @override
  String toString() => 'ScanPointsApiException: $message';
}
