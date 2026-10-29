import 'package:flutter/material.dart';
import '../state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController name;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: App.read(context).user?['name'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('profile'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${s.user?['phone'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'), filled: true, fillColor: Colors.white)),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () async {
            await s.saveName(name.text.trim());
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓')));
          },
          child: Text(s.t('save')),
        ),
        const SizedBox(height: 24),
        Text(s.t('language'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'tk', label: Text('Türkmençe')), ButtonSegment(value: 'ru', label: Text('Русский'))],
          selected: {s.lang},
          onSelectionChanged: (v) => s.setLang(v.first),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () => s.logout(),
          icon: const Icon(Icons.logout),
          label: Text(s.t('logout')),
        ),
      ]),
    );
  }
}
