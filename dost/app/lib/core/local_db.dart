import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local cache: the app opens instantly and works offline.
class LocalDb {
  Database? _db;

  Future<void> open(int userId) async {
    await close();
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'dost_$userId.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE chats(id INTEGER PRIMARY KEY, json TEXT NOT NULL)');
        await d.execute(
            'CREATE TABLE msgs(k TEXT PRIMARY KEY, id INTEGER NOT NULL, chat INTEGER NOT NULL, json TEXT NOT NULL)');
        await d.execute('CREATE INDEX msgs_chat ON msgs(chat, id)');
        await d.execute('CREATE INDEX msgs_id ON msgs(id)');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<Chat>> chats() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query('chats');
    return rows.map((r) => Chat.fromJson(jsonDecode(r['json'] as String))).toList();
  }

  Future<void> saveChats(Iterable<Chat> chats, {bool replaceAll = false}) async {
    final db = _db;
    if (db == null) return;
    final b = db.batch();
    if (replaceAll) b.delete('chats');
    for (final c in chats) {
      b.insert('chats', {'id': c.id, 'json': jsonEncode(c.toJson())},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<void> deleteChat(int id) async {
    await _db?.delete('chats', where: 'id=?', whereArgs: [id]);
    await _db?.delete('msgs', where: 'chat=?', whereArgs: [id]);
  }

  Future<void> saveMsgs(Iterable<Message> msgs) async {
    final db = _db;
    if (db == null) return;
    final b = db.batch();
    for (final m in msgs) {
      b.insert('msgs', {'k': m.key, 'id': m.id, 'chat': m.chat, 'json': jsonEncode(m.toJson())},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<void> deleteMsg(String key) async {
    await _db?.delete('msgs', where: 'k=?', whereArgs: [key]);
  }

  /// Latest [limit] messages of a chat, ascending; pending ones at the end.
  Future<List<Message>> msgs(int chat, {int limit = 80}) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery(
        'SELECT json FROM msgs WHERE chat=? ORDER BY (CASE WHEN id=0 THEN 9007199254740991 ELSE id END) DESC LIMIT ?',
        [chat, limit]);
    return rows.reversed.map((r) => Message.fromJson(jsonDecode(r['json'] as String))).toList();
  }

  Future<List<Message>> pending() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query('msgs', where: 'id=0');
    return rows.map((r) => Message.fromJson(jsonDecode(r['json'] as String))).toList();
  }

  Future<int> maxId() async {
    final db = _db;
    if (db == null) return 0;
    final r = await db.rawQuery('SELECT MAX(id) AS m FROM msgs');
    final v = r.first['m'];
    return v is int ? v : 0;
  }
}
