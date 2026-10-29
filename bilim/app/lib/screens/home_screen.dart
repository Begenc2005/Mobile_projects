import 'package:flutter/material.dart';
import '../models/content.dart';
import '../services/api.dart';
import '../services/l10n.dart';
import 'subject_screen.dart';
import 'lesson_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int grade = Api.I.grade;

  Future<void> _openReview() async {
    final items = <LessonItem>[];
    for (final (lid, idx) in Api.I.dueCards()) {
      final lesson = await Api.I.lesson(lid);
      if (lesson != null && idx < lesson.steps.length) items.add((lid, idx, lesson.steps[idx]));
    }
    if (!mounted || items.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen.review(items)));
    setState(() {});
  }

  Future<void> _continue(String lid) async {
    final lesson = await Api.I.lesson(lid);
    if (lesson == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson)));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = Api.I.lang, cs = Theme.of(context).colorScheme;
    final due = Api.I.dueCards().length;
    final last = Api.I.lastLesson;
    final subjects = Api.I.gradeSubjects(grade);
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text('${tr('hello', l)}, ${Api.I.name} 👋',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          Chip(avatar: const Text('🔥'), label: Text('${Api.I.streak}')),
          const SizedBox(width: 6),
          Chip(avatar: const Text('⭐'), label: Text('${Api.I.xp}')),
        ]),
        const SizedBox(height: 12),
        Card(
          color: cs.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.replay_circle_filled, size: 36),
            title: Text(tr('review', l), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(due > 0 ? '$due ${tr('review_due', l)}' : tr('review_none', l)),
            trailing: due > 0 ? const Icon(Icons.chevron_right) : null,
            onTap: due > 0 ? _openReview : null,
          ),
        ),
        if (last != null)
          Card(child: ListTile(
            leading: const Icon(Icons.play_circle_fill, size: 36),
            title: Text(tr('continue', l)),
            subtitle: Text(last),
            onTap: () => _continue(last),
          )),
        const SizedBox(height: 12),
        // grade picker 1–12
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 12,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text('${i + 1}'),
              selected: grade == i + 1,
              onSelected: (_) => setState(() { grade = i + 1; Api.I.grade = grade; }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('$grade ${tr('grade', l)} · ${tr('subjects', l)}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.45,
          children: [
            for (final s in subjects)
              _SubjectTile(Api.I.subjectMeta(s['id']), List<Map<String, dynamic>>.from(s['topics']), onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(s['id'], grade)));
                setState(() {});
              }),
          ],
        ),
      ]),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> topics;
  final VoidCallback onTap;
  const _SubjectTile(this.meta, this.topics, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse((meta['color'] as String).substring(1), radix: 16) | 0xFF000000);
    final lessons = topics.where((t) => t['lesson'] != null).toList();
    final done = lessons.where((t) => Api.I.best(t['lesson']) >= 0).length;
    return Material(
      color: color.withOpacity(.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meta['icon'], style: const TextStyle(fontSize: 26)),
            const Spacer(),
            Text(T.from(meta['title']).of(Api.I.lang), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('$done / ${lessons.length}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: lessons.isEmpty ? 0 : done / lessons.length, color: color,
                backgroundColor: color.withOpacity(.2), borderRadius: BorderRadius.circular(4)),
          ]),
        ),
      ),
    );
  }
}
