import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content.dart';

/// Server on Türkmentelekom. Override at build time:
/// flutter build apk --dart-define=API=https://bilim.tm
const apiBase = String.fromEnvironment('API', defaultValue: 'https://bilim.tm');

/// Demo build (no server, no SMS): flutter build apk --dart-define=DEMO=true
const demo = bool.fromEnvironment('DEMO');

/// Offline-first data layer:
///  • content: bundled in assets → refreshed from server with ETag → cached on device
///  • progress: saved locally first, queued in an outbox, synced when online
///  • review (Leitner boxes) computed on device so it works without internet
class Api {
  Api._();
  static final I = Api._();
  late SharedPreferences _p;
  final _subjects = <String, Subject>{};
  List<Map<String, dynamic>> manifest = [];
  Map<String, String> lessonIndex = {};
  List<Map<String, dynamic>> curriculum = [];

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final local = _p.getString('c:manifest') ??
        await rootBundle.loadString('assets/content/manifest.json');
    _applyManifest(local);
    _refresh('manifest').then((raw) { if (raw != null) _applyManifest(raw); });
    final cur = _p.getString('c:curriculum') ??
        await rootBundle.loadString('assets/content/curriculum.json');
    _applyCurriculum(cur);
    _refresh('curriculum').then((raw) { if (raw != null) _applyCurriculum(raw); });
    syncOutbox();
  }

  void _applyManifest(String raw) {
    final j = jsonDecode(raw);
    manifest = List<Map<String, dynamic>>.from(j['subjects']);
    lessonIndex = Map<String, String>.from(j['lessonIndex'] ?? {});
    _subjects.clear();
  }

  void _applyCurriculum(String raw) =>
      curriculum = List<Map<String, dynamic>>.from(jsonDecode(raw)['grades']);

  Map<String, dynamic> subjectMeta(String id) => manifest.firstWhere((s) => s['id'] == id);

  /// Subjects of a grade with their topics: [{id, topics:[{title, lesson|null}]}]
  List<Map<String, dynamic>> gradeSubjects(int g) {
    final row = curriculum.where((x) => x['grade'] == g);
    return row.isEmpty ? [] : List<Map<String, dynamic>>.from(row.first['subjects']);
  }

  int get grade => _p.getInt('grade') ?? 1;
  set grade(int v) => _p.setInt('grade', v);

  // ---------- auth ----------
  String? get token => _p.getString('token');
  String get lang => _p.getString('lang') ?? 'tk';
  set lang(String v) => _p.setString('lang', v);
  String get name => _p.getString('name') ?? '';
  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<String?> requestCode(String phone) async {
    if (demo) return '123456';
    final r = await http.post(Uri.parse('$apiBase/api/auth/request'),
        headers: _h, body: jsonEncode({'phone': phone}));
    if (r.statusCode != 200) throw Exception(r.body);
    return jsonDecode(r.body)['dev_code'] as String?;
  }

  Future<void> verify(String phone, String code, String name, int grade) async {
    if (demo) {
      await _p.setString('token', 'demo');
      await _p.setString('name', name.isEmpty ? 'Demo' : name);
      await _p.setInt('grade', grade);
      return;
    }
    final r = await http.post(Uri.parse('$apiBase/api/auth/verify'),
        headers: _h,
        body: jsonEncode({'phone': phone, 'code': code, 'name': name, 'grade': grade, 'lang': lang}));
    if (r.statusCode != 200) throw Exception(r.body);
    await _p.setString('token', jsonDecode(r.body)['token']);
    await _p.setString('name', name);
    await _p.setInt('grade', grade);
  }

  Future<void> logout() async => _p.remove('token');

  // ---------- content ----------
  Future<String?> _refresh(String name) async {
    if (demo) return null;
    try {
      final path = (name == 'manifest' || name == 'curriculum') ? name : 'subject/$name';
      final r = await http.get(Uri.parse('$apiBase/api/content/$path'),
          headers: {if (_p.getString('e:$name') != null) 'If-None-Match': _p.getString('e:$name')!})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final raw = utf8.decode(r.bodyBytes);
        await _p.setString('c:$name', raw);
        if (r.headers['etag'] != null) await _p.setString('e:$name', r.headers['etag']!);
        return raw;
      }
    } catch (_) {/* offline → cached copy */}
    return null;
  }

  Future<Subject> subject(String id) async {
    if (_subjects[id] != null) return _subjects[id]!;
    String? raw = _p.getString('c:$id') ?? await _refresh(id);
    raw ??= await rootBundle.loadString('assets/content/$id.json');
    _refresh(id); // update in background
    return _subjects[id] = Subject.from(jsonDecode(raw));
  }

  Future<Lesson?> lesson(String lessonId) async {
    final sid = lessonIndex[lessonId];
    if (sid == null) return null;
    final list = (await subject(sid)).lessons.where((x) => x.id == lessonId);
    return list.isEmpty ? null : list.first;
  }

  // ---------- progress, XP, streak (local first) ----------
  int best(String lessonId) => _p.getInt('b:$lessonId') ?? -1;
  int get xp => _p.getInt('xp') ?? 0;
  int get streak => _p.getInt('streak') ?? 0;
  String? get lastLesson => _p.getString('last');

  Future<void> saveResult(String lessonId, List<int> correct, List<int> wrong, int total) async {
    if (correct.length > best(lessonId)) await _p.setInt('b:$lessonId', correct.length);
    await _p.setString('last', lessonId);
    await _p.setInt('xp', xp + correct.length * 10);
    final today = _day(DateTime.now());
    final last = _p.getString('day');
    if (last != today) {
      final yest = _day(DateTime.now().subtract(const Duration(days: 1)));
      await _p.setInt('streak', last == yest ? streak + 1 : 1);
      await _p.setString('day', today);
    }
    _updateCards(lessonId, correct, wrong);
    final out = _p.getStringList('outbox') ?? [];
    out.add(jsonEncode({'lesson_id': lessonId, 'correct': correct, 'wrong': wrong, 'total': total}));
    await _p.setStringList('outbox', out);
    syncOutbox();
  }

  Future<void> syncOutbox() async {
    if (token == null || demo) return;
    final out = _p.getStringList('outbox') ?? [];
    while (out.isNotEmpty) {
      try {
        final r = await http.post(Uri.parse('$apiBase/api/progress'), headers: _h, body: out.first)
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) break;
        out.removeAt(0);
        await _p.setStringList('outbox', out);
      } catch (_) {
        break;
      }
    }
  }

  // ---------- spaced repetition: Leitner boxes 1,2,4,8,16,32 days ----------
  static const _days = [1, 2, 4, 8, 16, 32];
  String _day(DateTime d) => d.toIso8601String().substring(0, 10);
  Map<String, dynamic> get _cards => jsonDecode(_p.getString('cards') ?? '{}');

  void _updateCards(String lessonId, List<int> correct, List<int> wrong) {
    final c = _cards;
    final now = DateTime.now();
    for (final s in wrong) {
      c['$lessonId#$s'] = {'box': 0, 'due': _day(now.add(const Duration(days: 1)))};
    }
    for (final s in correct) {
      final k = '$lessonId#$s';
      if (c[k] != null) {
        final box = ((c[k]['box'] as int) + 1).clamp(0, _days.length - 1);
        c[k] = {'box': box, 'due': _day(now.add(Duration(days: _days[box])))};
      }
    }
    _p.setString('cards', jsonEncode(c));
  }

  /// Cards due today: list of (lessonId, stepIndex).
  List<(String, int)> dueCards() {
    final today = _day(DateTime.now());
    return _cards.entries
        .where((e) => (e.value['due'] as String).compareTo(today) <= 0)
        .map((e) {
      final parts = e.key.split('#');
      return (parts[0], int.parse(parts[1]));
    }).toList();
  }

  // ---------- help ----------
  Future<String> ask(String q, {String? lessonId, int? step}) async {
    if (demo) {
      await Future.delayed(const Duration(milliseconds: 700));
      return lang == 'ru'
          ? 'Это демо-версия: ответы репетитора доступны только при подключении к серверу. Уроки и тесты работают полностью.'
          : 'Bu demo wersiýa: mugallymyň jogaplary diňe serwere birikdirilende işleýär. Sapaklar we synaglar doly işleýär.';
    }
    try {
      final r = await http.post(Uri.parse('$apiBase/api/ask'),
          headers: _h,
          body: jsonEncode({'question': q, 'lesson_id': lessonId, 'step': step, 'lang': lang}))
          .timeout(const Duration(seconds: 35));
      return jsonDecode(utf8.decode(r.bodyBytes))['answer'];
    } catch (_) {
      return lang == 'ru' ? 'Нет связи. Попробуйте позже.' : 'Aragatnaşyk ýok. Soňrak synanyşyň.';
    }
  }

  Future<bool> support(String message) async {
    if (demo) return true;
    try {
      final r = await http.post(Uri.parse('$apiBase/api/support'),
          headers: _h, body: jsonEncode({'message': message}));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
