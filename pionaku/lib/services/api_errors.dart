class UnauthorizedException implements Exception {
  const UnauthorizedException([this.message]);

  final String? message;

  @override
  String toString() =>
      message == null ? 'UnauthorizedException' : 'UnauthorizedException: $message';
}

/// Thrown when a request exceeds [PionaHttpClient] timeout.
class ApiTimeoutException implements Exception {
  const ApiTimeoutException([this.message = 'Permintaan habis waktu.']);

  final String message;

  @override
  String toString() => 'ApiTimeoutException: $message';
}

