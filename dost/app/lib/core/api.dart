import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  ApiException(this.status, this.code);
  @override
  String toString() => 'ApiException($status, $code)';
}

/// REST client. dart:io sends "Accept-Encoding: gzip" and unpacks responses itself,
/// so chat lists and history travel compressed.
class Api {
  String? token;
  final http.Client _c = http.Client();

  Uri _u(String path, [Map<String, String>? q]) {
    final u = Uri.parse(Config.apiBase + path);
    return q == null ? u : u.replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _handle(http.Response r) {
    final body = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final code = body is Map && body['error'] is String ? body['error'] as String : 'error';
    throw ApiException(r.statusCode, code);
  }

  Future<dynamic> get(String path, [Map<String, String>? q]) async =>
      _handle(await _c.get(_u(path, q), headers: _headers).timeout(const Duration(seconds: 25)));

  Future<dynamic> post(String path, [Object? body]) async => _handle(await _c
      .post(_u(path), headers: _headers, body: jsonEncode(body ?? {}))
      .timeout(const Duration(seconds: 25)));

  Future<dynamic> put(String path, Object body) async => _handle(await _c
      .put(_u(path), headers: _headers, body: jsonEncode(body))
      .timeout(const Duration(seconds: 25)));

  Future<MediaInfo> upload(File file,
      {required String mime, int w = 0, int h = 0, int dur = 0}) async {
    final req = http.MultipartRequest('POST', _u('/api/media'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['mime'] = mime
      ..fields['w'] = '$w'
      ..fields['h'] = '$h'
      ..fields['d'] = '$dur'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await _c.send(req).timeout(const Duration(minutes: 3));
    final r = await http.Response.fromStream(streamed);
    return MediaInfo.fromJson(_handle(r) as Map<String, dynamic>);
  }

  String mediaUrl(String id) => '${Config.apiBase}/media/$id?t=$token';

  /// Download a media file once into [dest] (used for voice messages).
  Future<File> download(String id, File dest) async {
    final r = await _c
        .get(Uri.parse('${Config.apiBase}/media/$id'), headers: _headers)
        .timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) throw ApiException(r.statusCode, 'download');
    await dest.parent.create(recursive: true);
    return dest.writeAsBytes(r.bodyBytes, flush: true);
  }
}
