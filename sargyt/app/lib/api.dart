import 'dart:convert';
import 'package:http/http.dart' as http;
import 'demo_backend.dart';

/// Адрес сервера (на хостинге Türkmentelekom). Переопределяется при сборке:
/// flutter build apk --dart-define=API_URL=https://api.sargyt.tm
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

class ApiError implements Exception {
  final String code;
  final String message;
  ApiError(this.code, this.message);
  @override
  String toString() => message;
}

class Api {
  String? token;
  final http.Client _c = http.Client();

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<dynamic> _send(Future<http.Response> Function() fn) async {
    http.Response res;
    try {
      res = await fn().timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiError('network', 'network');
    }
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final m = body is Map ? body : const {};
      throw ApiError('${m['error'] ?? res.statusCode}', '${m['message'] ?? m['error'] ?? res.statusCode}');
    }
    return body;
  }

  Future<dynamic> get(String path) => demoMode ? DemoBackend.I.handle('GET', path) : _send(() => _c.get(Uri.parse('$apiUrl$path'), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) =>
      demoMode ? DemoBackend.I.handle('POST', path, body) : _send(() => _c.post(Uri.parse('$apiUrl$path'), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> patch(String path, Object body) =>
      demoMode ? DemoBackend.I.handle('PATCH', path, body) : _send(() => _c.patch(Uri.parse('$apiUrl$path'), headers: _headers, body: jsonEncode(body)));
}

double toD(dynamic v) => v == null ? 0 : (v as num).toDouble();
String money(dynamic v) => '${toD(v).toStringAsFixed(2)} TMT';
