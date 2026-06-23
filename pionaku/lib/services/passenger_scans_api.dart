import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_errors.dart';
import 'piona_http_client.dart';

class PassengerScansApi {
  PassengerScansApi({PionaHttpClient? httpClient})
      : _http = httpClient ?? PionaHttpClient.instance;

  final PionaHttpClient _http;

  Future<List<Map<String, dynamic>>> listPassengerScans({
    required String bearerToken,
    String? date,
    String? airportCode,
    List<String>? airportCodes,
    String? scanPoint,
    DateTime? since,
  }) async {
    final qp = <String, String>{};
    final d = date?.trim();
    if (d != null && d.isNotEmpty) qp['date'] = d;
    final acs = airportCodes
        ?.map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (acs != null && acs.isNotEmpty) {
      qp['airportCodes'] = acs.join(',');
    } else {
      final ac = airportCode?.trim();
      if (ac != null && ac.isNotEmpty) qp['airportCode'] = ac;
    }
    final sp = scanPoint?.trim();
    if (sp != null && sp.isNotEmpty) qp['scanPoint'] = sp;
    if (since != null) qp['since'] = since.toUtc().toIso8601String();

    final uri = _http.url('/passenger-scans', qp.isEmpty ? null : qp);
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const PassengerScansApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw PassengerScansApiException(msg ?? 'Gagal memuat passenger scans.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PassengerScansApiException(
          'Response passenger scans tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const PassengerScansApiException(
          'Daftar passenger scans tidak valid.');
    }
    return items
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  Future<List<String>> listAirports({required String bearerToken}) async {
    final uri = _http.url('/passenger-scans/airports');
    late final http.Response res;
    try {
      res = await _http.get(uri, bearerToken: bearerToken);
    } on ApiTimeoutException {
      throw const PassengerScansApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw PassengerScansApiException(msg ?? 'Gagal memuat daftar bandara.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PassengerScansApiException('Response airports tidak valid.');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const PassengerScansApiException('Daftar airports tidak valid.');
    }
    return items
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Future<({Map<String, dynamic> item, bool deduped})> createPassengerScan({
    required String bearerToken,
    required Map<String, Object?> body,
  }) async {
    final uri = _http.url('/passenger-scans');
    late final http.Response res;
    try {
      res = await _http.post(
        uri,
        body: jsonEncode(body),
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const PassengerScansApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = _tryExtractMessage(res.body);
      throw PassengerScansApiException(msg ?? 'Gagal menyimpan passenger scan.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PassengerScansApiException(
          'Response create scan tidak valid.');
    }
    final item = decoded['item'];
    final deduped = decoded['deduped'];
    if (item is! Map<String, dynamic>) {
      throw const PassengerScansApiException('Data scan tidak valid.');
    }
    return (item: item, deduped: deduped is bool ? deduped : false);
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

class PassengerScansApiException implements Exception {
  const PassengerScansApiException(this.message);

  final String message;

  @override
  String toString() => 'PassengerScansApiException: $message';
}
