import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/config.dart';
import '../core/fmt.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'auth_screens.dart' show LangSwitch;

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final me = app.me;
        if (me == null) return const SizedBox();
        return Scaffold(
          appBar: AppBar(title: Text(L.t('settings'))),
          body: ListView(children: [
            // profile card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: DostColors.brand, borderRadius: BorderRadius.circular(22)),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Avatar(id: me.id, name: me.name, mediaId: me.avatar, size: 64),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(me.name,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(prettyPhone(me.phone), style: const TextStyle(color: Colors.white70)),
                        if (me.about.isNotEmpty)
                          Text(me.about,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  ]),
                ),
              ),
            ),
            _section(context, L.t('language')),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: LangSwitch()),
            _section(context, L.t('theme')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                      value: ThemeMode.system, icon: const Icon(Icons.phone_android_rounded), label: Text(L.t('system'))),
                  ButtonSegment(
                      value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded), label: Text(L.t('light'))),
                  ButtonSegment(
                      value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded), label: Text(L.t('dark'))),
                ],
                selected: {app.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => app.setTheme(s.first),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              secondary: const Icon(Icons.image_outlined),
              title: Text(L.t('autoload_media')),
              value: app.autoLoadMedia,
              onChanged: app.setAutoLoad,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(L.t('about')),
              subtitle: Text('Dost ${Config.version}'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Dost',
                applicationVersion: Config.version,
                applicationIcon: const DostLogo(size: 48),
                children: [Text(L.t('tagline'))],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: DostColors.red),
              title: Text(L.t('logout'), style: const TextStyle(color: DostColors.red)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text(L.t('logout_q')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t('cancel'))),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(L.t('logout'), style: const TextStyle(color: DostColors.red))),
                    ],
                  ),
                );
                if (ok == true) await app.logout();
              },
            ),
            const SizedBox(height: 40),
          ]),
        );
      },
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: app.me?.name ?? '');
  late final _about = TextEditingController(text: app.me?.about ?? '');
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
      await app.updateProfile(name: _name.text, about: _about.text, avatar: _avatar);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = app.me!;
    return Scaffold(
      appBar: AppBar(title: Text(L.t('profile'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: GestureDetector(
            onTap: _pick,
            child: Stack(children: [
              _avatar != null
                  ? CircleAvatar(radius: 56, backgroundImage: FileImage(File(_avatar!.path)))
                  : Avatar(id: me.id, name: me.name, mediaId: me.avatar, size: 112),
              const Positioned(
                right: 2,
                bottom: 2,
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: DostColors.gold,
                  child: Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          maxLength: 64,
          decoration: InputDecoration(labelText: L.t('name'), counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _about,
          maxLength: 140,
          decoration: InputDecoration(labelText: L.t('about_me')),
        ),
        const SizedBox(height: 12),
        GradientButton(label: L.t('save'), loading: _loading, onTap: _save),
      ]),
    );
  }
}
