import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'tk', label: Text('Türkmen')),
        ButtonSegment(value: 'ru', label: Text('Русский')),
      ],
      selected: {app.lang},
      showSelectedIcon: false,
      onSelectionChanged: (s) {
        HapticFeedback.selectionClick();
        app.setLang(s.first);
      },
    );
  }
}

// ------------------------------------------------------------------ welcome

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: OrnamentBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const Spacer(flex: 3),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (_, v, c) => Transform.scale(scale: 0.5 + v * 0.5, child: c),
                child: const DostLogo(size: 120),
              ),
              const SizedBox(height: 28),
              Appear(
                delayMs: 150,
                child: ShaderMask(
                  shaderCallback: (r) => DostColors.brand.createShader(r),
                  child: const Text('Dost',
                      style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
                ),
              ),
              const SizedBox(height: 10),
              Appear(
                delayMs: 300,
                child: Text(L.t('tagline'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 17, height: 1.4, color: dark ? Colors.white70 : const Color(0xFF3F524B))),
              ),
              const Spacer(flex: 3),
              Appear(
                delayMs: 450,
                child: Column(children: [
                  Text(L.t('choose_lang'),
                      style: TextStyle(fontSize: 13, color: dark ? Colors.white54 : Colors.black45)),
                  const SizedBox(height: 10),
                  const LangSwitch(),
                ]),
              ),
              const SizedBox(height: 28),
              Appear(
                delayMs: 600,
                child: GradientButton(
                  label: L.t('start'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhoneScreen())),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ phone

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 8) d = d.substring(0, 8);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4 || i == 6) b.write(' ');
      b.write(d[i]);
    }
    final s = b.toString();
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  String get _digits => _ctrl.text.replaceAll(' ', '');

  Future<void> _submit() async {
    if (_digits.length != 8) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final phone = '+993$_digits';
    try {
      final dev = await app.requestCode(phone);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CodeScreen(phone: phone, devCode: dev)));
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.t('phone_title'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(L.t('phone_sub'), style: TextStyle(fontSize: 15, color: scheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 32),
            Row(children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).inputDecorationTheme.fillColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('🇹🇲  +993', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_PhoneFormatter()],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 1.5),
                  decoration: const InputDecoration(hintText: '65 12 34 56'),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ]),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox(height: 0, width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: DostColors.red)),
                    ),
            ),
            const Spacer(),
            GradientButton(
              label: L.t('next'),
              loading: _loading,
              onTap: _digits.length == 8 ? _submit : null,
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ code

class CodeScreen extends StatefulWidget {
  final String phone;
  final String? devCode;
  const CodeScreen({super.key, required this.phone, this.devCode});

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  String? _devCode;
  bool _loading = false;
  String? _error;
  int _left = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _left = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (_ctrl.text.length != 6 || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await app.verify(widget.phone, _ctrl.text);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _error = errorText(e);
        _ctrl.clear();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      final dev = await app.requestCode(widget.phone);
      setState(() => _devCode = dev);
      _startTimer();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.t('code_title'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(L.t('code_sub', {'phone': prettyPhone(widget.phone)}),
                style: TextStyle(fontSize: 15, color: scheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 32),
            AnimatedBuilder(
              animation: _shake,
              builder: (_, c) {
                final t = _shake.value;
                final dx = t == 0 ? 0.0 : 12 * (1 - t) * (((t * 8).floor().isEven) ? 1 : -1);
                return Transform.translate(offset: Offset(dx, 0), child: c);
              },
              child: GestureDetector(
                onTap: () => _focus.requestFocus(),
                child: Stack(children: [
                  // invisible real input
                  Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) {
                        setState(() => _error = null);
                        if (v.length == 6) _verify();
                      },
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _ctrl,
                    builder: (_, __) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (i) {
                        final ch = i < _ctrl.text.length ? _ctrl.text[i] : '';
                        final active = i == _ctrl.text.length;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 46,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context).inputDecorationTheme.fillColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _error != null
                                  ? DostColors.red
                                  : active
                                      ? scheme.primary
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: AnimatedScale(
                            scale: ch.isEmpty ? 0.4 : 1,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutBack,
                            child: Text(ch, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                          ),
                        );
                      }),
                    ),
                  ),
                ]),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_error!, style: const TextStyle(color: DostColors.red)),
              ),
            if (_devCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: ActionChip(
                  avatar: const Icon(Icons.bug_report_outlined, size: 18),
                  label: Text(L.t('test_code', {'code': _devCode!})),
                  onPressed: () {
                    _ctrl.text = _devCode!;
                    _verify();
                  },
                ),
              ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            const Spacer(),
            Center(
              child: _left > 0
                  ? Text(L.t('resend_in', {'s': '$_left'}),
                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)))
                  : TextButton(onPressed: _resend, child: Text(L.t('resend'))),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L.t('change_number')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ profile setup

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  XFile? _avatar;
  bool _loading = false;

  Future<void> _pick() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 75);
    if (f != null) setState(() => _avatar = f);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await app.updateProfile(name: _name.text, avatar: _avatar);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
          child: Column(children: [
            Text(L.t('profile_title'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(L.t('profile_sub'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: scheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 36),
            GestureDetector(
              onTap: _pick,
              child: Stack(children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _avatar == null ? DostColors.brand : null,
                    image: _avatar == null
                        ? null
                        : DecorationImage(image: FileImage(File(_avatar!.path)), fit: BoxFit.cover),
                  ),
                  child: _avatar == null
                      ? const Icon(Icons.person_rounded, size: 64, color: Colors.white)
                      : null,
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DostColors.gold,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 3),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 64,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(hintText: L.t('your_name'), counterText: ''),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const Spacer(),
            GradientButton(
              label: L.t('done'),
              loading: _loading,
              onTap: _name.text.trim().isEmpty ? null : _save,
            ),
          ]),
        ),
      ),
    );
  }
}
