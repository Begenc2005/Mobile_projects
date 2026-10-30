import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'demo_server.dart';
import 'l10n.dart';
import 'local_db.dart';
import 'models.dart';

enum NetState { offline, connecting, online }

/// Global app state (single instance [app]).
final app = AppState();

class AppState extends ChangeNotifier {
  final api = Api();
  final local = LocalDb();
  late SharedPreferences prefs;

  bool ready = false;
  User? me;
  String lang = 'tk';
  ThemeMode themeMode = ThemeMode.system;
  bool autoLoadMedia = true;

  final Map<int, Chat> chats = {};
  final Map<int, List<Message>> messages = {}; // ascending, only for opened chats
  final Map<int, bool> hasMore = {};
  final Map<int, Map<int, _Typing>> typing = {}; // chat -> user -> state
  List<User> contacts = [];
  NetState net = NetState.offline;
  int? openChat;

  WebSocket? _ws;
  Timer? _reconnectTimer;
  int _backoff = 1;
  bool _stopped = true;
  bool _connecting = false;
  final Set<String> _delivering = {};
  final _rand = Random.secure();

  // ---------------------------------------------------------------- startup

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'tk';
    L.lang = lang;
    themeMode = ThemeMode.values[prefs.getInt('theme') ?? 0];
    autoLoadMedia = prefs.getBool('autoload') ?? true;
    final token = prefs.getString('token');
    final meJson = prefs.getString('me');
    if (token != null && meJson != null) {
      api.token = token;
      me = User.fromJson(jsonDecode(meJson));
      await _startSession();
    }
    ready = true;
    notifyListeners();
  }

  bool get loggedIn => me != null && api.token != null;
  bool get needsProfile => me != null && me!.name.trim().isEmpty;
  int get myId => me?.id ?? 0;

  Future<void> _startSession() async {
    await local.open(me!.id);
    for (final c in await local.chats()) {
      chats[c.id] = c;
    }
    try {
      contacts = (jsonDecode(prefs.getString('contacts_${me!.id}') ?? '[]') as List)
          .map((e) => User.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    notifyListeners();
    _stopped = false;
    unawaited(_connect());
    unawaited(refreshChats());
    unawaited(refreshMe());
  }

  void setLang(String l) {
    lang = l;
    L.lang = l;
    prefs.setString('lang', l);
    if (loggedIn) api.put('/api/me', {'lang': l}).catchError((_) => null);
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    prefs.setInt('theme', m.index);
    notifyListeners();
  }

  void setAutoLoad(bool v) {
    autoLoadMedia = v;
    prefs.setBool('autoload', v);
    notifyListeners();
  }

  // ---------------------------------------------------------------- auth

  /// Returns the test code when the server runs in DEV mode.
  Future<String?> requestCode(String phone) async {
    final r = await api.post('/api/auth/code', {'phone': phone});
    return r['dev_code'] as String?;
  }

  Future<void> verify(String phone, String code) async {
    final r = await api.post('/api/auth/verify',
        {'phone': phone, 'code': code, 'device': Platform.operatingSystem});
    api.token = r['token'] as String;
    me = User.fromJson(r['user'] as Map<String, dynamic>);
    await prefs.setString('token', api.token!);
    await _saveMe();
    api.put('/api/me', {'lang': lang}).catchError((_) => null);
    await _startSession();
    notifyListeners();
  }

  Future<void> _saveMe() => prefs.setString('me', jsonEncode(me!.toJson()));

  Future<void> refreshMe() async {
    try {
      me = User.fromJson(await api.get('/api/me') as Map<String, dynamic>);
      await _saveMe();
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) await logout(remote: false);
    } catch (_) {}
  }

  Future<void> updateProfile({String? name, String? about, XFile? avatar}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name.trim();
    if (about != null) body['about'] = about.trim();
    if (avatar != null) {
      final info = await api.upload(File(avatar.path), mime: 'image/jpeg');
      body['avatar'] = info.id;
    }
    me = User.fromJson(await api.put('/api/me', body) as Map<String, dynamic>);
    await _saveMe();
    notifyListeners();
  }

  Future<void> logout({bool remote = true}) async {
    if (remote) {
      try {
        await api.post('/api/auth/logout');
      } catch (_) {}
    }
    _stopped = true;
    _reconnectTimer?.cancel();
    await _ws?.close();
    _ws = null;
    await prefs.remove('token');
    await prefs.remove('me');
    await local.close();
    chats.clear();
    messages.clear();
    contacts = [];
    api.token = null;
    me = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- realtime connection

  Future<void> _connect() async {
    if (_stopped || _ws != null || _connecting) return;
    if (demoMode) {
      net = NetState.online;
      notifyListeners();
      await _sync();
      return;
    }
    _connecting = true;
    net = NetState.connecting;
    notifyListeners();
    try {
      // permessage-deflate compression is on by default in dart:io
      final ws = await WebSocket.connect('${Config.wsBase}/ws?t=${api.token}',
              compression: CompressionOptions.compressionDefault)
          .timeout(const Duration(seconds: 15));
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      _connecting = false;
      _backoff = 1;
      net = NetState.online;
      notifyListeners();
      ws.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
      await _sync();
      await _flushOutbox();
    } catch (_) {
      _connecting = false;
      _onClosed();
    }
  }

  void _onClosed() {
    _ws = null;
    if (_stopped) return;
    net = NetState.offline;
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoff), _connect);
    _backoff = min(_backoff * 2, 30);
  }

  /// Called when the app returns to foreground.
  void reconnectNow() {
    if (_stopped) return;
    if (_ws == null && !_connecting) {
      _reconnectTimer?.cancel();
      _backoff = 1;
      _connect();
    }
  }

  bool _send(Map<String, dynamic> m) {
    if (demoMode) {
      DemoServer.I.frame(m, _onData);
      return true;
    }
    final ws = _ws;
    if (ws == null) return false;
    try {
      ws.add(jsonEncode(m));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'msg':
        _incoming(Message.fromJson(m['msg']), live: true);
      case 'ack':
        _incoming(Message.fromJson(m['msg']));
      case 'upd':
        _incoming(Message.fromJson(m['msg']));
      case 'read':
        final c = chats[m['chat']];
        final mem = c?.member(m['user'] as int);
        if (mem != null) {
          mem.read = max(mem.read, m['id'] as int);
          if (mem.id == myId) {
            c!.myRead = max(c.myRead, m['id'] as int);
            c.unread = 0;
          }
          notifyListeners();
        }
      case 'typing':
        _onTyping(m['chat'] as int, m['user'] as int, m['rec'] == true);
      case 'rx':
        _onReaction(m['chat'] as int, m['id'] as int, m['user'] as int, (m['e'] ?? '') as String);
      case 'pres':
        final uid = m['user'] as int;
        final on = m['on'] == true;
        for (final c in chats.values) {
          final mem = c.member(uid);
          if (mem != null) {
            mem.online = on;
            mem.seen = (m['seen'] ?? mem.seen) as int;
          }
        }
        notifyListeners();
      case 'chat':
        final c = Chat.fromJson(m['chat'] as Map<String, dynamic>);
        chats[c.id] = c;
        local.saveChats([c]);
        notifyListeners();
      case 'err':
        _markFailed(m['cid'] as String?);
    }
  }

  // ---------------------------------------------------------------- data sync

  Future<void> refreshChats() async {
    try {
      final list = (await api.get('/api/chats') as List)
          .map((e) => Chat.fromJson(e as Map<String, dynamic>))
          .toList();
      final pendingLast = {
        for (final c in chats.values)
          if (c.last?.pending == true) c.id: c.last
      };
      chats
        ..clear()
        ..addEntries(list.map((c) => MapEntry(c.id, c)));
      pendingLast.forEach((id, m) {
        if (chats[id] != null) chats[id]!.last = m;
      });
      if (openChat != null && chats[openChat] != null) chats[openChat]!.unread = 0;
      await local.saveChats(list, replaceAll: true);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) await logout(remote: false);
    } catch (_) {}
  }

  Future<Chat?> refreshChat(int id) async {
    try {
      final c = Chat.fromJson(await api.get('/api/chats/$id') as Map<String, dynamic>);
      chats[c.id] = c;
      await local.saveChats([c]);
      notifyListeners();
      return c;
    } catch (_) {
      return null;
    }
  }

  /// After reconnect: fetch everything missed while offline.
  Future<void> _sync() async {
    try {
      var after = await local.maxId();
      if (after > 0) {
        for (var i = 0; i < 10; i++) {
          final r = await api.get('/api/sync', {'after': '$after'}) as Map<String, dynamic>;
          final list = (r['msgs'] as List).map((e) => Message.fromJson(e)).toList();
          for (final msg in list) {
            _incoming(msg, notify: false);
          }
          if (list.isNotEmpty) after = list.last.id;
          if (r['more'] != true) break;
        }
      }
    } catch (_) {}
    await refreshChats();
    if (openChat != null) markRead(openChat!);
  }

  int _cmp(Message a, Message b) {
    if (a.pending && b.pending) return a.ts.compareTo(b.ts);
    if (a.pending) return 1;
    if (b.pending) return -1;
    return a.id.compareTo(b.id);
  }

  void _incoming(Message msg, {bool live = false, bool notify = true}) {
    var isNew = true;
    final list = messages[msg.chat];
    if (list != null) {
      final i = list.indexWhere((x) => x.key == msg.key || (!msg.pending && x.id == msg.id));
      if (i >= 0) {
        isNew = false;
        msg.localPath ??= list[i].localPath;
        list[i] = msg;
      } else {
        list.add(msg);
      }
      list.sort(_cmp);
    }
    local.saveMsgs([msg]);

    final c = chats[msg.chat];
    if (c == null) {
      refreshChat(msg.chat);
    } else {
      final last = c.last;
      if (last == null || last.key == msg.key || _cmp(msg, last) >= 0) c.last = msg;
      if (msg.from == myId) {
        if (!msg.pending) c.myRead = max(c.myRead, msg.id);
      } else if (live && isNew && msg.kind != kSystem) {
        _typingOff(msg.chat, msg.from);
        if (openChat == msg.chat) {
          markRead(msg.chat);
        } else {
          c.unread++;
          if (!c.muted) HapticFeedback.lightImpact();
        }
      }
      local.saveChats([c]);
    }
    if (notify) notifyListeners();
  }

  // ---------------------------------------------------------------- chat history

  Future<void> openChatScreen(int chatId) async {
    openChat = chatId;
    if (messages[chatId] == null) {
      messages[chatId] = await local.msgs(chatId);
      notifyListeners();
    }
    try {
      final fresh = (await api.get('/api/chats/$chatId/messages', {'limit': '50'}) as List)
          .map((e) => Message.fromJson(e))
          .toList()
          .reversed
          .toList();
      await local.saveMsgs(fresh);
      final cur = messages[chatId] ?? [];
      final cachedMax = cur.where((m) => !m.pending).fold<int>(0, (a, m) => max(a, m.id));
      if (fresh.isNotEmpty && fresh.first.id > cachedMax) {
        // gap between cache and server: start from the fresh page
        messages[chatId] = [...fresh, ...cur.where((m) => m.pending)];
      } else {
        final byKey = {for (final m in cur) m.key: m};
        for (final m in fresh) {
          m.localPath ??= byKey[m.key]?.localPath;
          byKey[m.key] = m;
        }
        messages[chatId] = byKey.values.toList()..sort(_cmp);
      }
      hasMore[chatId] = fresh.length >= 50;
      notifyListeners();
    } catch (_) {}
    markRead(chatId);
  }

  void closeChatScreen(int chatId) {
    if (openChat == chatId) openChat = null;
  }

  Future<bool> loadEarlier(int chatId) async {
    final list = messages[chatId];
    if (list == null || hasMore[chatId] == false) return false;
    final oldest = list.firstWhere((m) => !m.pending, orElse: () => list.first);
    if (oldest.pending) return false;
    try {
      final older = (await api.get('/api/chats/$chatId/messages',
              {'before': '${oldest.id}', 'limit': '50'}) as List)
          .map((e) => Message.fromJson(e))
          .toList();
      await local.saveMsgs(older);
      final keys = list.map((m) => m.key).toSet();
      list.insertAll(0, older.reversed.where((m) => !keys.contains(m.key)));
      hasMore[chatId] = older.length >= 50;
      notifyListeners();
      return older.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void markRead(int chatId) {
    final c = chats[chatId];
    if (c == null) return;
    var last = 0;
    for (final m in messages[chatId] ?? <Message>[]) {
      if (!m.pending && m.id > last) last = m.id;
    }
    if (c.last != null && !c.last!.pending) last = max(last, c.last!.id);
    if (last > c.myRead) {
      if (_send({'t': 'read', 'chat': chatId, 'id': last})) c.myRead = last;
    }
    if (c.unread != 0) {
      c.unread = 0;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- sending

  String _newCid() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 32).toRadixString(36)}';

  Message _pending(int chat, int kind, {String text = '', int reply = 0, MediaInfo? media, String? path}) =>
      Message(
        id: 0,
        chat: chat,
        from: myId,
        cid: _newCid(),
        kind: kind,
        text: text,
        reply: reply,
        media: media,
        localPath: path,
        ts: DateTime.now().millisecondsSinceEpoch,
        status: stPending,
      );

  void sendText(int chat, String text, {int reply = 0}) {
    final t = text.trim();
    if (t.isEmpty) return;
    final msg = _pending(chat, kText, text: t, reply: reply);
    _incoming(msg);
    _deliver(msg);
  }

  Future<void> sendImage(int chat, XFile file, {String caption = '', int reply = 0}) async {
    // copy into app storage so the image survives temp cleanup until uploaded
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/out/${_newCid()}.jpg');
    await dest.parent.create(recursive: true);
    await File(file.path).copy(dest.path);
    final bytes = await dest.readAsBytes();
    var w = 0, h = 0;
    try {
      final img = await decodeImageFromList(bytes);
      w = img.width;
      h = img.height;
      img.dispose();
    } catch (_) {}
    final msg = _pending(chat, kImage,
        text: caption.trim(),
        reply: reply,
        path: dest.path,
        media: MediaInfo(id: '', mime: 'image/jpeg', size: bytes.length, w: w, h: h));
    _incoming(msg);
    _deliver(msg);
  }

  void sendVoice(int chat, String path, int durationMs, {int reply = 0}) {
    final f = File(path);
    final msg = _pending(chat, kVoice,
        reply: reply,
        path: path,
        media: MediaInfo(id: '', mime: 'audio/mp4', size: f.existsSync() ? f.lengthSync() : 0, dur: durationMs));
    _incoming(msg);
    _deliver(msg);
  }

  void retry(Message m) {
    m.status = stPending;
    _incoming(m);
    _deliver(m);
  }

  Future<void> _deliver(Message m) async {
    if (_delivering.contains(m.key)) return;
    _delivering.add(m.key);
    try {
      final media = m.media;
      if (media != null && media.id.isEmpty) {
        final path = m.localPath;
        if (path == null || !File(path).existsSync()) {
          _markFailed(m.cid);
          return;
        }
        final info = await api.upload(File(path),
            mime: media.mime, w: media.w, h: media.h, dur: media.dur);
        m.media = MediaInfo(id: info.id, mime: info.mime, size: info.size, w: media.w, h: media.h, dur: media.dur);
        await local.saveMsgs([m]);
      }
      _send({
        't': 'send',
        'cid': m.cid,
        'chat': m.chat,
        'k': m.kind,
        if (m.text.isNotEmpty) 'tx': m.text,
        if (m.media != null) 'm': m.media!.id,
        if (m.reply > 0) 're': m.reply,
      });
      // if offline it stays pending and is re-sent by _flushOutbox on reconnect
    } catch (_) {
      // upload failed (bad network): show "retry"; also retried automatically on reconnect
      _markFailed(m.cid);
    } finally {
      _delivering.remove(m.key);
    }
  }

  Future<void> _flushOutbox() async {
    final list = await local.pending();
    list.sort((a, b) => a.ts.compareTo(b.ts));
    for (final m in list) {
      if (m.status == stFailed) {
        m.status = stPending;
        _incoming(m);
      }
      await _deliver(m);
    }
  }

  void _markFailed(String? cid) {
    if (cid == null) return;
    for (final list in messages.values) {
      for (final m in list) {
        if (m.cid == cid && m.from == myId && m.pending) {
          m.status = stFailed;
          local.saveMsgs([m]);
        }
      }
    }
    notifyListeners();
  }

  void editMessage(Message m, String text) {
    if (text.trim().isEmpty) return;
    _send({'t': 'edit', 'id': m.id, 'tx': text.trim()});
  }

  void deleteMessage(Message m) {
    if (m.pending) {
      // never reached the server: just drop it locally
      messages[m.chat]?.removeWhere((x) => x.key == m.key);
      local.deleteMsg(m.key);
      notifyListeners();
      return;
    }
    _send({'t': 'del', 'id': m.id});
  }

  void react(Message m, String emoji) {
    if (m.pending) return;
    final mine = m.rx.entries.where((e) => e.value.contains(myId)).map((e) => e.key).firstOrNull;
    final e = mine == emoji ? '' : emoji; // tap same emoji again = remove
    _onReaction(m.chat, m.id, myId, e); // optimistic
    _send({'t': 'react', 'id': m.id, 'e': e});
    HapticFeedback.selectionClick();
  }

  void _onReaction(int chat, int msgId, int user, String e) {
    final list = messages[chat];
    if (list == null) return;
    for (final m in list) {
      if (m.id == msgId) {
        for (final v in m.rx.values) {
          v.remove(user);
        }
        m.rx.removeWhere((k, v) => v.isEmpty);
        if (e.isNotEmpty) m.rx.putIfAbsent(e, () => []).add(user);
        local.saveMsgs([m]);
        notifyListeners();
        return;
      }
    }
  }

  // ---------------------------------------------------------------- typing

  DateTime _lastTypingSent = DateTime(2000);

  void sendTyping(int chat, {bool recording = false}) {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inSeconds < 3) return;
    _lastTypingSent = now;
    _send({'t': 'typing', 'chat': chat, if (recording) 'rec': true});
  }

  void _onTyping(int chat, int user, bool rec) {
    if (user == myId) return;
    final map = typing.putIfAbsent(chat, () => {});
    map[user]?.timer.cancel();
    map[user] = _Typing(rec, Timer(const Duration(seconds: 5), () => _typingOff(chat, user)));
    notifyListeners();
  }

  void _typingOff(int chat, int user) {
    final t = typing[chat]?.remove(user);
    if (t != null) {
      t.timer.cancel();
      notifyListeners();
    }
  }

  /// "typing…" / "recording…" / null
  String? typingText(int chat) {
    final map = typing[chat];
    if (map == null || map.isEmpty) return null;
    final rec = map.values.any((t) => t.rec);
    final c = chats[chat];
    final word = L.t(rec ? 'recording' : 'typing');
    if (c != null && c.isGroup) {
      final name = c.member(map.keys.first)?.name ?? '';
      return '$name $word';
    }
    return word;
  }

  // ---------------------------------------------------------------- chats & contacts

  Future<Chat> openDirect(int userId) async {
    for (final c in chats.values) {
      if (!c.isGroup && c.member(userId) != null) return c;
    }
    final c = Chat.fromJson(await api.post('/api/chats/direct', {'user': userId}) as Map<String, dynamic>);
    chats[c.id] = c;
    await local.saveChats([c]);
    notifyListeners();
    return c;
  }

  Future<Chat> createGroup(String title, List<int> members) async {
    final c = Chat.fromJson(
        await api.post('/api/chats/group', {'title': title, 'members': members}) as Map<String, dynamic>);
    chats[c.id] = c;
    await local.saveChats([c]);
    notifyListeners();
    return c;
  }

  Future<void> leaveGroup(int chatId) async {
    await api.post('/api/chats/$chatId/leave');
    chats.remove(chatId);
    messages.remove(chatId);
    await local.deleteChat(chatId);
    notifyListeners();
  }

  Future<void> setMuted(Chat c, bool muted) async {
    c.muted = muted;
    notifyListeners();
    await local.saveChats([c]);
    try {
      await api.put('/api/chats/${c.id}/mute', {'muted': muted});
    } catch (_) {}
  }

  Future<User?> findByPhone(String phone) async {
    try {
      return User.fromJson(await api.get('/api/users/search', {'phone': phone}) as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 400) return null;
      rethrow;
    }
  }

  /// Match the phone book against registered users.
  Future<bool> syncContacts() async {
    if (!await FlutterContacts.requestPermission(readonly: true)) return false;
    final book = await FlutterContacts.getContacts(withProperties: true);
    final phones = <String>{};
    for (final c in book) {
      for (final p in c.phones) {
        final digits = p.number.replaceAll(RegExp(r'[^0-9+]'), '');
        if (digits.length >= 8) phones.add(digits);
      }
    }
    final list = (await api.post('/api/users/lookup', {'phones': phones.take(3000).toList()}) as List)
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    contacts = list;
    await prefs.setString('contacts_$myId', jsonEncode(list.map((u) => u.toJson()).toList()));
    notifyListeners();
    return true;
  }

  List<Chat> get sortedChats => chats.values.toList()..sort((a, b) => b.sortTs.compareTo(a.sortTs));

  int get totalUnread => chats.values.fold(0, (a, c) => a + (c.muted ? 0 : c.unread));

  /// Where a voice message is cached locally.
  Future<File> voiceFile(String mediaId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/voice/$mediaId.m4a');
  }
}

class _Typing {
  final bool rec;
  final Timer timer;
  _Typing(this.rec, this.timer);
}
