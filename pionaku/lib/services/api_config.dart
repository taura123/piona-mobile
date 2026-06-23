class ApiConfig {
  ApiConfig._();

  /// Backend base URL.
  ///
  /// - Android emulator: use `http://10.0.2.2:8080`
  /// - Real device: use your PC/LAN IP, e.g. `http://192.168.1.10:8080`
  static const String baseUrl = String.fromEnvironment(
    'PIONA_API_BASE_URL',
    defaultValue: 'http://192.168.1.103:8080',
  );
}

