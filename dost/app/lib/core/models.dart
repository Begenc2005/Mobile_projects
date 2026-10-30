// Data models. JSON keys are short to save traffic (must match the Go server).

int _i(dynamic v) => v is num ? v.toInt() : 0;
String _s(dynamic v) => v is String ? v : '';

const kChatDirect = 1;
const kChatGroup = 2;

const kText = 1;
const kImage = 2;
const kVoice = 3;
const kSystem = 4;

// local delivery status
const stPending = 0;
const stSent = 1;
const stFailed = 2;

class User {
  final int id;
  String phone, name, about, avatar, lang;
  int seen;
  bool online;

  User({
    required this.id,
    this.phone = '',
    this.name = '',
    this.about = '',
    this.avatar = '',
    this.lang = '',
    this.seen = 0,
    this.online = false,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: _i(j['id']),
        phone: _s(j['phone']),
        name: _s(j['name']),
        about: _s(j['about']),
        avatar: _s(j['avatar']),
        lang: _s(j['lang']),
        seen: _i(j['seen']),
        online: j['on'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'about': about,
        'avatar': avatar,
        'lang': lang,
        'seen': seen,
        'on': online,
      };
}

class MediaInfo {
  String id; // empty = not uploaded yet
  final String mime;
  final int size, w, h, dur;

  MediaInfo({
    required this.id,
    required this.mime,
    this.size = 0,
    this.w = 0,
    this.h = 0,
    this.dur = 0,
  });

  factory MediaInfo.fromJson(Map<String, dynamic> j) => MediaInfo(
        id: _s(j['id']),
        mime: _s(j['mt']),
        size: _i(j['sz']),
        w: _i(j['w']),
        h: _i(j['h']),
        dur: _i(j['d']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'mt': mime, 'sz': size, 'w': w, 'h': h, 'd': dur};
}

class Message {
  int id; // 0 while pending
  final int chat, from;
  final String cid;
  final int kind;
  String text;
  MediaInfo? media;
  final int reply;
  int ts;
  bool edited, deleted;
  Map<String, List<int>> rx;
  int status;
  String? localPath; // local file of media we sent (shown before/after upload)

  Message({
    required this.id,
    required this.chat,
    required this.from,
    required this.cid,
    required this.kind,
    this.text = '',
    this.media,
    this.reply = 0,
    required this.ts,
    this.edited = false,
    this.deleted = false,
    Map<String, List<int>>? rx,
    this.status = stSent,
    this.localPath,
  }) : rx = rx ?? {};

  /// unique key: cid is unique per sender
  String get key => '$from:$cid';
  bool get pending => id == 0;

  factory Message.fromJson(Map<String, dynamic> j) {
    final rx = <String, List<int>>{};
    final r = j['rx'];
    if (r is Map) {
      r.forEach((k, v) {
        if (v is List) rx[k.toString()] = v.map(_i).toList();
      });
    }
    final m = j['m'];
    return Message(
      id: _i(j['id']),
      chat: _i(j['chat']),
      from: _i(j['from']),
      cid: _s(j['cid']),
      kind: _i(j['k']),
      text: _s(j['tx']),
      media: m is Map<String, dynamic> ? MediaInfo.fromJson(m) : null,
      reply: _i(j['re']),
      ts: _i(j['ts']),
      edited: j['ed'] == true,
      deleted: j['del'] == true,
      rx: rx,
      status: j.containsKey('st') ? _i(j['st']) : stSent,
      localPath: j['lp'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat': chat,
        'from': from,
        'cid': cid,
        'k': kind,
        'tx': text,
        if (media != null) 'm': media!.toJson(),
        're': reply,
        'ts': ts,
        'ed': edited,
        'del': deleted,
        'rx': rx,
        'st': status,
        if (localPath != null) 'lp': localPath,
      };
}

class Member {
  final int id;
  String name, phone, avatar;
  int seen, read, role;
  bool online;

  Member({
    required this.id,
    this.name = '',
    this.phone = '',
    this.avatar = '',
    this.seen = 0,
    this.read = 0,
    this.role = 0,
    this.online = false,
  });

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: _i(j['id']),
        name: _s(j['name']),
        phone: _s(j['phone']),
        avatar: _s(j['avatar']),
        seen: _i(j['seen']),
        read: _i(j['rd']),
        role: _i(j['role']),
        online: j['on'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'avatar': avatar,
        'seen': seen,
        'rd': read,
        'role': role,
        'on': online,
      };
}

class Chat {
  final int id, kind;
  String title, avatar;
  List<Member> members;
  Message? last;
  int unread, myRead, created;
  bool muted;

  Chat({
    required this.id,
    required this.kind,
    this.title = '',
    this.avatar = '',
    List<Member>? members,
    this.last,
    this.unread = 0,
    this.myRead = 0,
    this.created = 0,
    this.muted = false,
  }) : members = members ?? [];

  bool get isGroup => kind == kChatGroup;

  Member? peer(int me) {
    for (final m in members) {
      if (m.id != me) return m;
    }
    return null;
  }

  Member? member(int id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  String displayTitle(int me) =>
      isGroup ? title : (peer(me)?.name.isNotEmpty == true ? peer(me)!.name : peer(me)?.phone ?? '');

  String displayAvatar(int me) => isGroup ? avatar : (peer(me)?.avatar ?? '');

  /// highest message id read by anyone except me (for ✓✓)
  int othersRead(int me) {
    var r = 0;
    for (final m in members) {
      if (m.id != me && m.read > r) r = m.read;
    }
    return r;
  }

  int get sortTs => last?.ts ?? created;

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: _i(j['id']),
        kind: _i(j['kind']),
        title: _s(j['title']),
        avatar: _s(j['avatar']),
        members: (j['members'] as List? ?? [])
            .map((e) => Member.fromJson(e as Map<String, dynamic>))
            .toList(),
        last: j['last'] is Map<String, dynamic> ? Message.fromJson(j['last']) : null,
        unread: _i(j['unread']),
        myRead: _i(j['myRead']),
        created: _i(j['created']),
        muted: j['muted'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'avatar': avatar,
        'members': members.map((m) => m.toJson()).toList(),
        if (last != null) 'last': last!.toJson(),
        'unread': unread,
        'myRead': myRead,
        'created': created,
        'muted': muted,
      };
}
