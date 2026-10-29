import 'package:flutter/material.dart';
import '../state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(text: '+993 ');
  final code = TextEditingController();
  final name = TextEditingController();
  bool codeSent = false, busy = false;
  String? error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() { busy = true; error = null; });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = App.read(context).err(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'tk', label: Text('TM')), ButtonSegment(value: 'ru', label: Text('RU'))],
                  selected: {s.lang},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => s.setLang(v.first),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Text('SARGYT', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 4),
            const Text('Aşgabat · Mary · Balkanabat', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 40),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              enabled: !codeSent,
              decoration: InputDecoration(labelText: s.t('phone'), border: const OutlineInputBorder()),
            ),
            if (codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                decoration: InputDecoration(labelText: s.t('code'), border: const OutlineInputBorder()),
              ),
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'), border: const OutlineInputBorder())),
            ],
            const SizedBox(height: 16),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => _run(() async {
                        if (!codeSent) {
                          final dev = await s.requestCode(phone.text);
                          setState(() { codeSent = true; if (dev != null) code.text = dev; });
                        } else {
                          await s.verify(phone.text, code.text.trim(), name.text.trim());
                        }
                      }),
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(codeSent ? s.t('enter') : s.t('getCode')),
            ),
            if (codeSent)
              TextButton(onPressed: () => setState(() { codeSent = false; code.clear(); }), child: Text(s.t('phone'))),
          ],
        ),
      ),
    );
  }
}
