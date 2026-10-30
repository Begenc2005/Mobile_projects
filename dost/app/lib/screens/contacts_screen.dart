import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

Future<void> startChatWith(BuildContext context, User u, {bool replace = false}) async {
  try {
    final c = await app.openDirect(u.id);
    if (!context.mounted) return;
    final route = MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id));
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
  }
}

/// Phone book matches + search by number.
class ContactList extends StatefulWidget {
  final void Function(User u) onTap;
  final Set<int>? selected;
  const ContactList({super.key, required this.onTap, this.selected});

  @override
  State<ContactList> createState() => _ContactListState();
}

class _ContactListState extends State<ContactList> {
  final _phone = TextEditingController();
  bool _syncing = false;
  bool _searching = false;
  User? _found;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    if (app.contacts.isEmpty) _sync(silent: true);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sync({bool silent = false}) async {
    setState(() => _syncing = true);
    try {
      final ok = await app.syncContacts();
      if (!ok && !silent && mounted) toast(context, L.t('contacts_perm'));
    } catch (e) {
      if (!silent && mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _search() async {
    final d = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (d.length != 8) return;
    setState(() {
      _searching = true;
      _found = null;
      _notFound = false;
    });
    try {
      final u = await app.findByPhone('+993$d');
      setState(() {
        _found = u;
        _notFound = u == null;
      });
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Widget _tile(User u) {
    final sel = widget.selected;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Avatar(id: u.id, name: u.name, mediaId: u.avatar, size: 48, online: u.online),
      title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(u.about.isNotEmpty ? u.about : prettyPhone(u.phone), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: sel == null
          ? null
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: sel.contains(u.id)
                  ? const Icon(Icons.check_circle_rounded, key: ValueKey(1), color: DostColors.emerald, size: 28)
                  : Icon(Icons.radio_button_unchecked_rounded,
                      key: const ValueKey(0), color: Theme.of(context).dividerColor, size: 28),
            ),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap(u);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.contacts;
        return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: L.t('find_by_phone'),
                prefixText: '+993 ',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                if (_found != null || _notFound) {
                  setState(() {
                    _found = null;
                    _notFound = false;
                  });
                }
              },
            ),
          ),
          if (_found != null) Appear(child: _tile(_found!)),
          if (_notFound)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(L.t('not_found'), style: TextStyle(color: muted)),
            ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: DostColors.gold.withValues(alpha: 0.2),
              child: const Icon(Icons.card_giftcard_rounded, color: DostColors.gold),
            ),
            title: Text(L.t('invite')),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: L.t('invite_text')));
              if (context.mounted) toast(context, L.t('invite_copied'));
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            child: Row(children: [
              Text(L.t('on_dost').toUpperCase(),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6)),
              const Spacer(),
              _syncing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(onPressed: () => _sync(), icon: const Icon(Icons.sync_rounded)),
            ]),
          ),
          if (list.isEmpty && !_syncing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(L.t('no_contacts'), style: TextStyle(color: muted)),
                const SizedBox(height: 10),
                FilledButton.tonal(onPressed: () => _sync(), child: Text(L.t('allow'))),
              ]),
            ),
          for (var i = 0; i < list.length; i++) Appear(delayMs: i < 12 ? i * 25 : 0, child: _tile(list[i])),
        ]);
      },
    );
  }
}

class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('contacts'))),
      body: ContactList(onTap: (u) => startChatWith(context, u)),
    );
  }
}

class PickContactScreen extends StatelessWidget {
  const PickContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('new_chat'))),
      body: ContactList(onTap: (u) => startChatWith(context, u, replace: true)),
    );
  }
}

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _title = TextEditingController();
  final Set<int> _sel = {};
  bool _loading = false;

  Future<void> _create() async {
    if (_title.text.trim().isEmpty || _sel.isEmpty) return;
    setState(() => _loading = true);
    try {
      final c = await app.createGroup(_title.text.trim(), _sel.toList());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _title.text.trim().isNotEmpty && _sel.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(L.t('new_group'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(gradient: DostColors.brand, shape: BoxShape.circle),
              child: const Icon(Icons.groups_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _title,
                maxLength: 64,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: L.t('group_name'), counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${L.t('select_members')} · ${_sel.length}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        Expanded(
          child: ContactList(
            selected: _sel,
            onTap: (u) => setState(() => _sel.contains(u.id) ? _sel.remove(u.id) : _sel.add(u.id)),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: GradientButton(label: L.t('create'), loading: _loading, onTap: ready ? _create : null),
          ),
        ),
      ]),
    );
  }
}
