import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/l10n.dart';

/// Chat-style help: AI tutor (if enabled on server) → lesson hint → support ticket.
class HelpScreen extends StatefulWidget {
  final String? lessonId;
  final int? step;
  const HelpScreen({super.key, this.lessonId, this.step});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final msgs = <(bool, String)>[]; // (fromUser, text)
  final ctrl = TextEditingController();
  bool busy = false;

  Future<void> _send() async {
    final q = ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { msgs.add((true, q)); busy = true; ctrl.clear(); });
    final a = await Api.I.ask(q, lessonId: widget.lessonId, step: widget.step);
    if (mounted) setState(() { msgs.add((false, a)); busy = false; });
  }

  @override
  Widget build(BuildContext context) {
    final l = Api.I.lang, cs = Theme.of(context).colorScheme;
    final all = [(false, tr('tutor_hi', l)), ...msgs];
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.support_agent),
        title: Text(tr('support', l)),
        subtitle: Text(l == 'ru' ? 'Ответим живым человеком' : 'Adam jogap berer'),
        trailing: const Icon(Icons.mail_outline),
        onTap: () async {
          if (ctrl.text.trim().isEmpty) return;
          final ok = await Api.I.support(ctrl.text.trim());
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '✓' : '✗')));
          if (ok) ctrl.clear();
        },
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: all.length,
          itemBuilder: (_, k) {
            final (mine, text) = all[k];
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(text),
              ),
            );
          },
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl, minLines: 1, maxLines: 4,
                decoration: InputDecoration(hintText: tr('ask', l), border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: busy ? null : _send, icon: const Icon(Icons.send)),
          ]),
        ),
      ),
    ]);
  }
}
