import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_errors.dart';

/// Shared HTTP policy: base URL, timeout, optional debug logging.
///
/// Callers still interpret status codes; [UnauthorizedException] is not
/// thrown here so APIs can attach domain-specific messages.
class PionaHttpClient {
  PionaHttpClient({
    http.Client? inner,
    this.defaultTimeout = const Duration(seconds: 30),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration defaultTimeout;

  static final PionaHttpClient instance = PionaHttpClient();

  String _baseTrimmed() {
    var b = ApiConfig.baseUrl.trim();
    if (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  /// Absolute URI under [ApiConfig.baseUrl] with optional query string.
  Uri url(String path, [Map<String, String>? queryParameters]) {
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse('${_baseTrimmed()}$p');
    if (queryParameters == null || queryParameters.isEmpty) {
      return u;
    }
    final merged = Map<String, String>.from(u.queryParameters);
    merged.addAll(queryParameters);
    return u.replace(queryParameters: merged);
  }

  Future<http.Response> get(
    Uri uri, {
    String? bearerToken,
    bool withJsonContentType = true,
    Map<String, String>? extraHeaders,
    Duration? timeout,
  }) {
    final req = http.Request('GET', uri);
    if (withJsonContentType) {
      req.headers['Content-Type'] = 'application/json';
    }
    _applyAuth(req, bearerToken);
    extraHeaders?.forEach((String k, String v) => req.headers[k] = v);
    return _send(req, timeout);
  }

  Future<http.Response> post(
    Uri uri, {
    required String body,
    String? bearerToken,
    bool withJsonContentType = true,
    Duration? timeout,
  }) {
    final req = http.Request('POST', uri)..body = body;
    if (withJsonContentType) {
      req.headers['Content-Type'] = 'application/json';
    }
    _applyAuth(req, bearerToken);
    return _send(req, timeout);
  }

  Future<http.Response> put(
    Uri uri, {
    required String body,
    String? bearerToken,
    Duration? timeout,
  }) {
    final req = http.Request('PUT', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = body;
    _applyAuth(req, bearerToken);
    return _send(req, timeout);
  }

  Future<http.Response> delete(
    Uri uri, {
    String? bearerToken,
    bool withJsonContentType = false,
    Duration? timeout,
  }) {
    final req = http.Request('DELETE', uri);
    if (withJsonContentType) {
      req.headers['Content-Type'] = 'application/json';
    }
    _applyAuth(req, bearerToken);
    return _send(req, timeout);
  }

  void _applyAuth(http.BaseRequest req, String? bearerToken) {
    final t = bearerToken?.trim();
    if (t != null && t.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $t';
    }
  }

  Future<http.Response> _send(http.BaseRequest req, Duration? timeout) async {
    final dur = timeout ?? defaultTimeout;
    try {
      if (kDebugMode) {
        debugPrint('PionaHTTP ${req.method} ${req.url}');
      }
      final streamed = await _inner.send(req).timeout(dur);
      final res = await http.Response.fromStream(streamed);
      if (kDebugMode) {
        debugPrint('PionaHTTP ${res.statusCode} ${req.url}');
      }
      return res;
    } on TimeoutException {
      throw const ApiTimeoutException();
    }
  }
}
