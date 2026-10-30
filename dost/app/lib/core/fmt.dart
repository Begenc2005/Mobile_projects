import 'l10n.dart';

String two(int n) => n.toString().padLeft(2, '0');

DateTime _d(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String hhmm(int ms) {
  final d = _d(ms);
  return '${two(d.hour)}:${two(d.minute)}';
}

/// Chat list time: 14:05 / Yesterday / 12.03.26
String shortTime(int ms) {
  if (ms == 0) return '';
  final d = _d(ms);
  final now = DateTime.now();
  if (sameDay(d, now)) return hhmm(ms);
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return L.t('yesterday');
  return '${two(d.day)}.${two(d.month)}.${two(d.year % 100)}';
}

/// Date separator inside a chat
String dayLabel(int ms) {
  final d = _d(ms);
  final now = DateTime.now();
  if (sameDay(d, now)) return L.t('today');
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return L.t('yesterday');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String lastSeen(int ms) {
  if (ms == 0) return L.t('last_seen_recent');
  final d = _d(ms);
  final now = DateTime.now();
  final String when;
  if (sameDay(d, now)) {
    when = hhmm(ms);
  } else if (sameDay(d, now.subtract(const Duration(days: 1)))) {
    when = '${L.t('yesterday').toLowerCase()} ${hhmm(ms)}';
  } else {
    when = '${two(d.day)}.${two(d.month)}';
  }
  return L.t('last_seen', {'time': when});
}

String duration(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${two(s % 60)}';
}

/// +99365123456 -> +993 65 12 34 56
String prettyPhone(String p) {
  if (p.length == 12 && p.startsWith('+993')) {
    return '+993 ${p.substring(4, 6)} ${p.substring(6, 8)} ${p.substring(8, 10)} ${p.substring(10)}';
  }
  return p;
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters1.toUpperCase();
  return (parts[0].characters1 + parts[1].characters1).toUpperCase();
}

extension on String {
  String get characters1 => isEmpty ? '' : String.fromCharCode(runes.first);
}
