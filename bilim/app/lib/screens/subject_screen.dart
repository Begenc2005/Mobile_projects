import 'package:flutter/material.dart' hide Step;
import '../models/content.dart';
import '../services/api.dart';
import '../services/l10n.dart';
import 'lesson_screen.dart';

/// Topics of one subject in one grade, in teaching order.
class SubjectScreen extends StatefulWidget {
  final String id;
  final int grade;
  const SubjectScreen(this.id, this.grade, {super.key});
  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  late final Future<Subject> _f = Api.I.subject(widget.id);

  @override
  Widget build(BuildContext context) {
    final l = Api.I.lang;
    final meta = Api.I.subjectMeta(widget.id);
    final color = Color(int.parse((meta['color'] as String).substring(1), radix: 16) | 0xFF000000);
    final row = Api.I.gradeSubjects(widget.grade).where((s) => s['id'] == widget.id);
    final topics = row.isEmpty ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(row.first['topics']);
    return Scaffold(
      appBar: AppBar(
        title: Text('${meta['icon']}  ${T.from(meta['title']).of(l)} · ${widget.grade}'),
        backgroundColor: color.withOpacity(.15),
      ),
      body: FutureBuilder<Subject>(
        future: _f,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final byId = {for (final x in snap.data!.lessons) x.id: x};
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: topics.length,
            itemBuilder: (_, i) {
              final t = topics[i];
              final lesson = byId[t['lesson']];
              final best = lesson == null ? -1 : Api.I.best(lesson.id);
              return Card(
                child: ListTile(
                  enabled: lesson != null,
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(.15),
                    child: best >= 0 ? Icon(Icons.check, color: color) : Text('${i + 1}', style: TextStyle(color: color)),
                  ),
                  title: Text(T.from(t['title']).of(l)),
                  subtitle: Text(lesson == null
                      ? (l == 'ru' ? 'Скоро' : 'Taýýarlanýar')
                      : '${lesson.minutes} ${tr('min', l)} · ${best >= 0 ? '$best/${lesson.questions}' : '${lesson.questions} ?'}'),
                  trailing: lesson == null ? null : const Icon(Icons.chevron_right),
                  onTap: lesson == null ? null : () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson, color: color)));
                    setState(() {});
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
