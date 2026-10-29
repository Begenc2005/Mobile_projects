/// Bilingual text: {"tk": "...", "ru": "..."} or a plain string (same in both).
class T {
  final String tk, ru;
  const T(this.tk, this.ru);
  factory T.from(dynamic j) =>
      j is String ? T(j, j) : T(j['tk'] as String, j['ru'] as String);
  String of(String lang) => lang == 'ru' ? ru : tk;
}

enum StepType { theory, example, choice, input, truefalse, world }

class Step {
  final StepType type;
  final T? text, q, hint, explain;
  final List<T> options;
  final dynamic answer; // int (choice) | String "a|b" (input) | bool (truefalse)

  Step(this.type, {this.text, this.q, this.hint, this.explain, this.options = const [], this.answer});

  bool get isQuestion =>
      type == StepType.choice || type == StepType.input || type == StepType.truefalse;

  factory Step.from(Map<String, dynamic> j) => Step(
        StepType.values.byName(j['type']),
        text: j['text'] == null ? null : T.from(j['text']),
        q: j['q'] == null ? null : T.from(j['q']),
        hint: j['hint'] == null ? null : T.from(j['hint']),
        explain: j['explain'] == null ? null : T.from(j['explain']),
        options: (j['options'] as List? ?? []).map(T.from).toList(),
        answer: j['answer'],
      );

  /// Normalises typed answers: trims, lowercases, accepts "," as decimal point.
  bool checkInput(String value) {
    String n(String s) => s.trim().toLowerCase().replaceAll(',', '.').replaceAll('’', "'").replaceAll('−', '-').replaceAll(' ', '');
    return (answer as String).split('|').any((a) => n(a) == n(value));
  }
}

class Lesson {
  final String id;
  final int grade, minutes;
  final T title;
  final List<Step> steps;
  Lesson(this.id, this.grade, this.minutes, this.title, this.steps);
  factory Lesson.from(Map<String, dynamic> j) => Lesson(
        j['id'], j['grade'], j['minutes'] ?? 10, T.from(j['title']),
        (j['steps'] as List).map((s) => Step.from(s)).toList(),
      );
  int get questions => steps.where((s) => s.isQuestion).length;
}

class Subject {
  final String id, icon;
  final int color;
  final T title;
  final List<Lesson> lessons;
  Subject(this.id, this.icon, this.color, this.title, this.lessons);
  factory Subject.from(Map<String, dynamic> j) => Subject(
        j['id'], j['icon'],
        int.parse((j['color'] as String).substring(1), radix: 16) | 0xFF000000,
        T.from(j['title']),
        (j['lessons'] as List).map((l) => Lesson.from(l)).toList(),
      );
}
