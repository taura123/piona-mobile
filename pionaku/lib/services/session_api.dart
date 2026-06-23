import 'package:http/http.dart' as http;

import 'api_errors.dart';
import 'piona_http_client.dart';

class SessionApi {
  SessionApi({PionaHttpClient? httpClient})
      : _http = httpClient ?? PionaHttpClient.instance;

  final PionaHttpClient _http;

  Future<void> ping({required String bearerToken}) async {
    final uri = _http.url('/session/ping');
    late final http.Response res;
    try {
      res = await _http.post(
        uri,
        body: '{}',
        bearerToken: bearerToken,
      );
    } on ApiTimeoutException {
      throw const SessionApiException('Permintaan habis waktu.');
    }
    if (res.statusCode == 401) {
      throw const UnauthorizedException('Session expired.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const SessionApiException('Gagal ping session.');
    }
  }
}

class SessionApiException implements Exception {
  const SessionApiException(this.message);

  final String message;

  @override
  String toString() => 'SessionApiException: $message';
}
