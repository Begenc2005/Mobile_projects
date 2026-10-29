import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api.dart';
import '../services/l10n.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = Api.I.lang;
    return ListView(padding: const EdgeInsets.all(16), children: [
      CircleAvatar(radius: 36, child: Text(Api.I.name.isEmpty ? '?' : Api.I.name[0], style: const TextStyle(fontSize: 28))),
      const SizedBox(height: 8),
      Center(child: Text(Api.I.name, style: Theme.of(context).textTheme.titleLarge)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _Stat('⭐', '${Api.I.xp}', tr('xp', l))),
        Expanded(child: _Stat('🔥', '${Api.I.streak}', tr('streak', l))),
      ]),
      const SizedBox(height: 16),
      ListTile(
        leading: const Icon(Icons.language),
        title: Text(tr('lang', l)),
        trailing: SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'tk', label: Text('TK')), ButtonSegment(value: 'ru', label: Text('RU'))],
          selected: {l},
          onSelectionChanged: (s) { Api.I.lang = s.first; refreshApp(); },
        ),
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: Text(tr('logout', l)),
        onTap: () async { await Api.I.logout(); refreshApp(); },
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String icon, value, label;
  const _Stat(this.icon, this.value, this.label);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ]),
        ),
      );
}
