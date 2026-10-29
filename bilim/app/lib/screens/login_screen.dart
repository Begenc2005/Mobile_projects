import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api.dart';
import '../services/l10n.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(text: '+993 6');
  final code = TextEditingController();
  final name = TextEditingController();
  int grade = 7;
  bool sent = false, busy = false;
  String? error;

  String get _phone => phone.text.replaceAll(RegExp(r'[^\d+]'), '');

  Future<void> _go() async {
    setState(() { busy = true; error = null; });
    try {
      if (!sent) {
        final dev = await Api.I.requestCode(_phone);
        if (dev != null) code.text = dev; // test servers only
        sent = true;
      } else {
        await Api.I.verify(_phone, code.text.trim(), name.text.trim(), grade);
        refreshApp();
      }
    } catch (e) {
      error = Api.I.lang == 'ru' ? 'Ошибка. Проверьте данные.' : 'Ýalňyşlyk. Maglumatlary barlaň.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = Api.I.lang;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 32),
          Text('Bilim', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(l == 'ru' ? 'Школа и репетитор в телефоне' : 'Mekdep we mugallym telefonyňyzda'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'tk', label: Text('Türkmençe')), ButtonSegment(value: 'ru', label: Text('Русский'))],
            selected: {l},
            onSelectionChanged: (s) { Api.I.lang = s.first; refreshApp(); },
          ),
          const SizedBox(height: 24),
          TextField(controller: phone, keyboardType: TextInputType.phone, enabled: !sent,
              decoration: InputDecoration(labelText: tr('phone', l), border: const OutlineInputBorder())),
          if (sent) ...[
            const SizedBox(height: 12),
            TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6,
                decoration: InputDecoration(labelText: tr('code', l), border: const OutlineInputBorder())),
            TextField(controller: name, decoration: InputDecoration(labelText: tr('name', l), border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: grade,
              decoration: InputDecoration(labelText: tr('grade', l), border: const OutlineInputBorder()),
              items: [for (var g = 1; g <= 12; g++) DropdownMenuItem(value: g, child: Text('$g ${tr('grade', l)}'))],
              onChanged: (v) => grade = v ?? grade,
            ),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _go,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(sent ? tr('login', l) : tr('get_code', l)),
          ),
        ]),
      ),
    );
  }
}
