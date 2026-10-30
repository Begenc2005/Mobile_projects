/// Server address. Override at build time:
///   flutter build apk --dart-define=DOST_API=https://api.dost.tm
class Config {
  static const apiBase =
      String.fromEnvironment('DOST_API', defaultValue: 'https://api.dost.tm');

  /// https -> wss, http -> ws
  static String get wsBase => apiBase.replaceFirst('http', 'ws');

  static const version = '0.1.0';
}
