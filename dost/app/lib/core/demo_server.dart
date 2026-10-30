import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'api.dart';
import 'models.dart';

/// Demo build (no server, no SMS): flutter build apk --dart-define=DEMO=true
/// Login code is always 123456. Chats are local; contacts answer with canned replies.
const bool demoMode = bool.fromEnvironment('DEMO');

typedef J = Map<String, dynamic>;

class DemoServer {
  DemoServer._();
  static final I = DemoServer._();

  static const meId = 1;
  final _rand = Random();
  int _nextMsg = 100;
  int _nextChat = 10;
  bool _ready = false;

  final Map<int, J> users = {
    1: {'id': 1, 'phone': '+99361000001', 'name': 'Demo', 'about': '', 'avatar': '', 'lang': 'tk', 'seen': 0, 'on': true},
    2: {'id': 2, 'phone': '+99361000002', 'name': 'Aman', 'about': 'Ashgabat', 'avatar': '', 'lang': 'tk', 'seen': 0, 'on': true},
    3: {'id': 3, 'phone': '+99361000003', 'name': 'Maral', 'about': '', 'avatar': '', 'lang': 'ru', 'seen': 0, 'on': false},
    4: {'id': 4, 'phone': '+99361000004', 'name': 'Dost bot', 'about': 'Demo', 'avatar': '', 'lang': 'tk', 'seen': 0, 'on': true},
  };
  final Map<int, J> chats = {};
  final Map<int, List<J>> msgs = {};

  J _member(int id, {int rd = 0, int role = 0}) {
    final u = users[id]!;
    return {'id': id, 'name': u['name'], 'phone': u['phone'], 'avatar': '', 'seen': u['seen'], 'rd': rd, 'role': role, 'on': u['on']};
  }

  J _msg(int chat, int from, String text, {String? cid, int? ts}) => {
        'id': _nextMsg++, 'chat': chat, 'from': from, 'cid': cid ?? 'd${_nextMsg}',
        'k': kText, 'tx': text, 're': 0, 'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
        'ed': false, 'del': false, 'rx': <String, dynamic>{},
      };

  void _seed() {
    if (_ready) return;
    _ready = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    void mk(int id, int kind, String title, List<int> members, List<(int, String)> talk) {
      final list = <J>[];
      var t = now - talk.length * 60000 * 7;
      for (final (from, text) in talk) {
        list.add(_msg(id, from, text, ts: t += 60000 * 7));
      }
      msgs[id] = list;
      chats[id] = {
        'id': id, 'kind': kind, 'title': title, 'avatar': '',
        'members': [for (final m in members) _member(m, rd: m == meId ? list.last['id'] : 0)],
        'last': list.isEmpty ? null : list.last, 'unread': 0, 'myRead': list.isEmpty ? 0 : list.last['id'],
        'created': now - 86400000, 'muted': false,
      };
    }

    mk(1, kChatDirect, '', [1, 2], [
      (2, 'Salam! Dost programmasyny synap görýärsiňmi?'),
      (1, 'Hawa, gaty gowy işleýär 👍'),
      (2, 'Super! Bir zat ýaz, men jogap bererin.'),
    ]);
    mk(2, kChatDirect, '', [1, 3], [
      (3, 'Привет! Это демо-чат.'),
      (3, 'Напиши мне что-нибудь 🙂'),
    ]);
    mk(3, kChatDirect, '', [1, 4], [
      (4, 'Dost-a hoş geldiňiz! Bu demo wersiýa: habarlar diňe şu telefonda saklanýar.'),
    ]);
    mk(4, kChatGroup, 'Demo topar', [1, 2, 3], [
      (2, 'Ählimize salam!'),
      (3, 'Всем привет 👋'),
    ]);
    chats[3]!['unread'] = 1;
    chats[3]!['myRead'] = 0;
    chats[4]!['unread'] = 0;
  }

  static const _repliesTk = ['Düşündim 👍', 'Gaty gowy!', 'Ýene aýdyp bilersiňmi?', 'Hawa, kabul 🙂', 'Ajaýyp pikir!'];
  static const _repliesRu = ['Понял 👍', 'Отлично!', 'Хорошо, договорились 🙂', 'Интересно!', 'Согласен'];

  String _reply(int who) {
    final l = who == 3 ? _repliesRu : _repliesTk;
    return l[_rand.nextInt(l.length)];
  }

  J _chatView(J c) {
    final list = msgs[c['id']] ?? [];
    return {...c, 'last': list.isEmpty ? null : list.last};
  }

  // ---------------------------------------------------------------- REST
  Future<dynamic> rest(String method, String path, [Map<String, String>? q, Object? body]) async {
    _seed();
    await Future.delayed(const Duration(milliseconds: 150));
    final b = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
    final seg = Uri.parse(path).pathSegments; // api, x, ...

    if (seg[1] == 'auth') {
      if (seg[2] == 'code') return {'ok': true, 'dev_code': '123456'};
      if (seg[2] == 'verify') {
        if ('${b['code']}' != '123456') throw ApiException(400, 'bad_code');
        if (b['phone'] != null) users[meId]!['phone'] = b['phone'];
        return {'token': 'demo', 'user': users[meId]};
      }
      return {'ok': true};
    }
    if (seg[1] == 'me') {
      if (method == 'PUT') {
        for (final k in ['name', 'about', 'lang']) {
          if (b[k] != null) users[meId]![k] = b[k];
        }
      }
      return users[meId];
    }
    if (seg[1] == 'users') {
      if (seg.length > 2 && seg[2] == 'search') {
        final ph = (q?['phone'] ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
        for (final u in users.values) {
          if (u['id'] != meId && (u['phone'] as String).endsWith(ph.length > 4 ? ph.substring(ph.length - 6) : '###')) return u;
        }
        throw ApiException(404, 'not_found');
      }
      if (seg.length > 2 && seg[2] == 'lookup') return [for (final u in users.values) if (u['id'] != meId) u];
      final u = users[int.tryParse(seg.last)];
      if (u == null) throw ApiException(404, 'not_found');
      return u;
    }
    if (seg[1] == 'sync') return {'msgs': <J>[], 'more': false};
    if (seg[1] == 'chats') {
      if (seg.length == 2) return [for (final c in chats.values) _chatView(c)];
      if (seg[2] == 'direct') {
        final uid = b['user'] as int;
        for (final c in chats.values) {
          if (c['kind'] == kChatDirect && (c['members'] as List).any((m) => m['id'] == uid)) return _chatView(c);
        }
        final id = _nextChat++;
        chats[id] = {'id': id, 'kind': kChatDirect, 'title': '', 'avatar': '', 'members': [_member(meId), _member(uid)],
          'last': null, 'unread': 0, 'myRead': 0, 'created': DateTime.now().millisecondsSinceEpoch, 'muted': false};
        msgs[id] = [];
        return _chatView(chats[id]!);
      }
      if (seg[2] == 'group') {
        final id = _nextChat++;
        final ids = {meId, ...List<int>.from(b['members'] ?? [])};
        chats[id] = {'id': id, 'kind': kChatGroup, 'title': b['title'] ?? 'Topar', 'avatar': '',
          'members': [for (final m in ids) _member(m, role: m == meId ? 1 : 0)],
          'last': null, 'unread': 0, 'myRead': 0, 'created': DateTime.now().millisecondsSinceEpoch, 'muted': false};
        msgs[id] = [];
        return _chatView(chats[id]!);
      }
      final id = int.parse(seg[2]);
      final c = chats[id];
      if (c == null) throw ApiException(404, 'not_found');
      if (seg.length == 3) return _chatView(c);
      switch (seg[3]) {
        case 'messages':
          final list = msgs[id] ?? [];
          final before = int.tryParse(q?['before'] ?? '') ?? 1 << 30;
          final limit = int.tryParse(q?['limit'] ?? '') ?? 50;
          final older = list.where((m) => (m['id'] as int) < before).toList().reversed.take(limit).toList();
          return older; // newest first
        case 'leave':
          chats.remove(id);
          return {'ok': true};
        case 'mute':
          c['muted'] = b['muted'] == true;
          return {'ok': true};
      }
      return {'ok': true};
    }
    throw ApiException(404, 'not_found');
  }

  // ---------------------------------------------------------------- realtime frames
  void frame(Map<String, dynamic> f, void Function(String) emit) {
    _seed();
    void out(J m) => emit(jsonEncode(m));
    switch (f['t']) {
      case 'send':
        final chat = f['chat'] as int;
        final m = _msg(chat, meId, '${f['tx'] ?? ''}', cid: f['cid'] as String?);
        m['k'] = f['k'] ?? kText;
        m['re'] = f['re'] ?? 0;
        (msgs[chat] ??= []).add(m);
        Future.delayed(const Duration(milliseconds: 150), () => out({'t': 'ack', 'msg': m}));
        final c = chats[chat];
        if (c == null) return;
        final others = [for (final x in c['members'] as List) if (x['id'] != meId) x['id'] as int];
        if (others.isEmpty) return;
        final who = others.length == 1 ? others.first : others[_rand.nextInt(others.length)];
        Future.delayed(const Duration(milliseconds: 900), () => out({'t': 'typing', 'chat': chat, 'user': who}));
        Future.delayed(const Duration(milliseconds: 2400), () {
          final r = _msg(chat, who, _reply(who));
          msgs[chat]!.add(r);
          out({'t': 'msg', 'msg': r});
        });
      case 'edit':
        for (final list in msgs.values) {
          for (final m in list) {
            if (m['id'] == f['id']) {
              m['tx'] = f['tx'];
              m['ed'] = true;
              Future.delayed(const Duration(milliseconds: 100), () => out({'t': 'upd', 'msg': m}));
            }
          }
        }
      case 'del':
        for (final list in msgs.values) {
          for (final m in list) {
            if (m['id'] == f['id']) {
              m['del'] = true;
              m['tx'] = '';
              Future.delayed(const Duration(milliseconds: 100), () => out({'t': 'upd', 'msg': m}));
            }
          }
        }
      default:
        break;
    }
  }
}
