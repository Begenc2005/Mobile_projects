import 'package:flutter/material.dart' hide Step;
import '../models/content.dart';
import '../services/api.dart';
import '../services/l10n.dart';
import 'help_screen.dart';

/// (lessonId, stepIndex, step)
typedef LessonItem = (String, int, Step);

/// Step-by-step player: theory → example → questions (hint, check, explanation) → world fact → result.
/// The same player runs a lesson or a review session built from due cards.
class LessonScreen extends StatefulWidget {
  final List<LessonItem> items;
  final String title;
  final Color? color;
  final int questions;

  LessonScreen(Lesson lesson, {super.key, this.color})
      : items = [for (var i = 0; i < lesson.steps.length; i++) (lesson.id, i, lesson.steps[i])],
        title = lesson.title.of(Api.I.lang),
        questions = lesson.questions;

  LessonScreen.review(this.items, {super.key, this.color})
      : title = tr('review', Api.I.lang),
        questions = items.length;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int i = 0;
  int? picked;
  bool? tf;
  bool checked = false, hintShown = false, ok = false;
  final input = TextEditingController();
  final correct = <String, List<int>>{}, wrong = <String, List<int>>{};

  String get l => Api.I.lang;
  LessonItem get item => widget.items[i];
  Step get step => item.$3;
  bool get finished => i >= widget.items.length;

  bool get canCheck => switch (step.type) {
        StepType.choice => picked != null,
        StepType.truefalse => tf != null,
        StepType.input => input.text.trim().isNotEmpty,
        _ => true,
      };

  void _check() {
    ok = switch (step.type) {
      StepType.choice => picked == step.answer,
      StepType.truefalse => tf == step.answer,
      StepType.input => step.checkInput(input.text),
      _ => true,
    };
    final firstTry = ok && !hintShown; // a hint means "review later"
    (firstTry ? correct : wrong).putIfAbsent(item.$1, () => []).add(item.$2);
    setState(() => checked = true);
  }

  Future<void> _next() async {
    setState(() {
      i++;
      picked = null; tf = null; checked = false; hintShown = false; ok = false;
      input.clear();
    });
    if (finished) {
      final ids = {...correct.keys, ...wrong.keys};
      for (final id in ids) {
        await Api.I.saveResult(id, correct[id] ?? [], wrong[id] ?? [], widget.questions);
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.color ?? cs.primary;
    if (finished) return _result(color);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr('help', l),
            icon: const Icon(Icons.support_agent),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => Scaffold(appBar: AppBar(title: Text(tr('help', l))),
                    body: HelpScreen(lessonId: item.$1, step: item.$2)))),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(value: i / widget.items.length, color: color, minHeight: 6),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: ListView(padding: const EdgeInsets.all(20), children: _body(cs, color))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              if (step.isQuestion && !checked && step.hint != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OutlinedButton.icon(
                    onPressed: hintShown ? null : () => setState(() => hintShown = true),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: Text(tr('hint', l)),
                  ),
                ),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: color),
                  onPressed: step.isQuestion && !checked ? (canCheck ? _check : null) : _next,
                  child: Text(step.isQuestion && !checked ? tr('check', l) : tr('next', l)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _body(ColorScheme cs, Color color) {
    final big = Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.45);
    switch (step.type) {
      case StepType.theory:
      case StepType.example:
        return [
          Text(step.type == StepType.example ? (l == 'ru' ? 'Пример' : 'Mysal') : (l == 'ru' ? 'Теория' : 'Nazaryýet'),
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: step.type == StepType.example ? color.withOpacity(.08) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(step.text!.of(l), style: big),
          ),
        ];
      case StepType.world:
        return [
          Text('🌍 ${tr('world', l)}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(step.text!.of(l), style: big))),
        ];
      default:
        return [
          Text(step.q!.of(l), style: big?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ..._answers(cs, color),
          if (hintShown && !checked) _note('💡 ${step.hint!.of(l)}', cs.tertiaryContainer),
          if (checked)
            _note('${ok ? tr('correct', l) : tr('wrong', l)}\n${step.explain?.of(l) ?? ''}',
                ok ? Colors.green.withOpacity(.15) : cs.errorContainer),
        ];
    }
  }

  List<Widget> _answers(ColorScheme cs, Color color) {
    Widget option(String label, bool selected, bool? isRight, VoidCallback onTap) {
      Color? bg;
      if (checked && isRight == true) bg = Colors.green.withOpacity(.18);
      if (checked && selected && isRight == false) bg = cs.errorContainer;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: bg ?? (selected ? color.withOpacity(.12) : cs.surfaceContainerHighest.withOpacity(.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: selected ? color : Colors.transparent, width: 2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: checked ? null : onTap,
            child: Padding(padding: const EdgeInsets.all(16), child: Text(label, style: const TextStyle(fontSize: 16))),
          ),
        ),
      );
    }

    switch (step.type) {
      case StepType.choice:
        return [
          for (var k = 0; k < step.options.length; k++)
            option(step.options[k].of(l), picked == k, k == step.answer, () => setState(() => picked = k)),
        ];
      case StepType.truefalse:
        return [
          option('✓ ${tr('true', l)}', tf == true, step.answer == true, () => setState(() => tf = true)),
          option('✗ ${tr('false', l)}', tf == false, step.answer == false, () => setState(() => tf = false)),
        ];
      default:
        return [
          TextField(
            controller: input,
            enabled: !checked,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => canCheck && !checked ? _check() : null,
            decoration: InputDecoration(labelText: tr('answer_here', l), border: const OutlineInputBorder()),
          ),
          if (checked && !ok) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text('= ${(step.answer as String).split('|').first}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ];
    }
  }

  Widget _note(String text, Color bg) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
      );

  Widget _result(Color color) {
    final right = correct.values.fold<int>(0, (a, b) => a + b.length);
    final total = widget.questions;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(right == total ? '🏆' : right * 2 >= total ? '👍' : '💪', style: const TextStyle(fontSize: 72)),
            const SizedBox(height: 12),
            Text(tr('done', l), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${tr('score', l)}: $right / $total'),
            Text('+${right * 10} ${tr('xp', l)} · 🔥 ${Api.I.streak} ${tr('streak', l)}'),
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: color),
              onPressed: () => Navigator.pop(context),
              child: Text(tr('finish', l)),
            ),
            TextButton(
              onPressed: () => setState(() { i = 0; correct.clear(); wrong.clear(); }),
              child: Text(tr('retry', l)),
            ),
          ]),
        ),
      ),
    );
  }
}
