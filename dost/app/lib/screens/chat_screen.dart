import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/voice.dart';
import 'home_screen.dart' show StatusIcon;

const _quickReactions = ['❤️', '👍', '😂', '😮', '😢', '🙏', '🔥'];

class ChatScreen extends StatefulWidget {
  final int chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final Set<String> _known = {};
  bool _loadingEarlier = false;
  bool _showDown = false;
  Message? _replyTo;
  Message? _editing;
  final _composerKey = GlobalKey<_ComposerState>();

  int get id => widget.chatId;

  @override
  void initState() {
    super.initState();
    app.openChatScreen(id);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    app.closeChatScreen(id);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scroll.position;
    final down = pos.pixels > 400;
    if (down != _showDown) setState(() => _showDown = down);
    if (pos.pixels > pos.maxScrollExtent - 400 && !_loadingEarlier && app.hasMore[id] != false) {
      _loadingEarlier = true;
      app.loadEarlier(id).whenComplete(() {
        _known.addAll((app.messages[id] ?? []).map((m) => m.key));
        _loadingEarlier = false;
      });
    }
  }

  void _toBottom() {
    _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  void _setReply(Message m) {
    HapticFeedback.selectionClick();
    setState(() {
      _editing = null;
      _replyTo = m;
    });
    _composerKey.currentState?.focus();
  }

  void _setEdit(Message m) {
    setState(() {
      _replyTo = null;
      _editing = m;
    });
    _composerKey.currentState?.setText(m.text);
  }

  String _senderName(Chat c, int uid) =>
      uid == app.myId ? L.t('you') : (c.member(uid)?.name ?? '');

  Future<void> _menu(Message m) async {
    HapticFeedback.mediumImpact();
    final mine = m.from == app.myId;
    final res = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!m.pending)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < _quickReactions.length; i++)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 250 + i * 50),
                      curve: Curves.easeOutBack,
                      builder: (_, v, c) => Transform.scale(scale: v, child: c),
                      child: InkResponse(
                        onTap: () => Navigator.pop(ctx, 'rx:${_quickReactions[i]}'),
                        radius: 26,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(_quickReactions[i], style: const TextStyle(fontSize: 30)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (!m.pending)
            ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(L.t('reply')),
                onTap: () => Navigator.pop(ctx, 'reply')),
          if (m.kind == kText)
            ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(L.t('copy')),
                onTap: () => Navigator.pop(ctx, 'copy')),
          if (mine && m.kind == kText && !m.pending)
            ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(L.t('edit')),
                onTap: () => Navigator.pop(ctx, 'edit')),
          if (m.status == stFailed)
            ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: Text(L.t('retry')),
                onTap: () => Navigator.pop(ctx, 'retry')),
          if (mine)
            ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: DostColors.red),
                title: Text(L.t('delete'), style: const TextStyle(color: DostColors.red)),
                onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || res == null) return;
    if (res.startsWith('rx:')) {
      app.react(m, res.substring(3));
    } else if (res == 'reply') {
      _setReply(m);
    } else if (res == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) toast(context, L.t('copied'));
    } else if (res == 'edit') {
      _setEdit(m);
    } else if (res == 'retry') {
      app.retry(m);
    } else if (res == 'delete') {
      final ok = m.pending ||
          await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  content: Text(L.t('delete_q')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L.t('cancel'))),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(L.t('delete'), style: const TextStyle(color: DostColors.red))),
                  ],
                ),
              ) ==
              true;
      if (ok) app.deleteMessage(m);
    }
  }

  void _showInfo(Chat c) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, sc) => ListView(controller: sc, children: [
          Center(
            child: Avatar(
              id: c.isGroup ? c.id : (c.peer(app.myId)?.id ?? c.id),
              name: c.displayTitle(app.myId),
              mediaId: c.displayAvatar(app.myId),
              size: 96,
              group: c.isGroup,
            ),
          ),
          const SizedBox(height: 12),
          Center(
              child: Text(c.displayTitle(app.myId),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          if (!c.isGroup && c.peer(app.myId) != null)
            Center(child: Text(prettyPhone(c.peer(app.myId)!.phone))),
          const SizedBox(height: 12),
          if (c.isGroup) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(L.t('members_count', {'n': '${c.members.length}'}),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final m in c.members)
              ListTile(
                leading: Avatar(id: m.id, name: m.name, mediaId: m.avatar, size: 42, online: m.online),
                title: Text(m.id == app.myId ? '${m.name} (${L.t('you')})' : m.name),
                subtitle: Text(m.online ? L.t('online') : lastSeen(m.seen)),
              ),
          ],
          ListTile(
            leading: Icon(c.muted ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            title: Text(L.t(c.muted ? 'unmute' : 'mute')),
            onTap: () {
              app.setMuted(c, !c.muted);
              Navigator.pop(ctx);
            },
          ),
          if (c.isGroup)
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: DostColors.red),
              title: Text(L.t('leave_group'), style: const TextStyle(color: DostColors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await app.leaveGroup(c.id);
                  if (mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (mounted) toast(context, errorText(e));
                }
              },
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.chats[id];
        if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final me = app.myId;
        final msgs = app.messages[id] ?? const <Message>[];
        if (_known.isEmpty && msgs.isNotEmpty) _known.addAll(msgs.map((m) => m.key));
        final peer = c.peer(me);
        final typing = app.typingText(id);
        final scheme = Theme.of(context).colorScheme;
        final String status = typing ??
            (c.isGroup
                ? L.t('members_count', {'n': '${c.members.length}'})
                : (peer?.online ?? false)
                    ? L.t('online')
                    : lastSeen(peer?.seen ?? 0));
        final byId = {for (final m in msgs) if (!m.pending) m.id: m};

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              onTap: () => _showInfo(c),
              child: Row(children: [
                Hero(
                  tag: 'avatar-${c.id}',
                  child: Avatar(
                    id: c.isGroup ? c.id : (peer?.id ?? c.id),
                    name: c.displayTitle(me),
                    mediaId: c.displayAvatar(me),
                    size: 40,
                    online: !c.isGroup && (peer?.online ?? false),
                    group: c.isGroup,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.displayTitle(me),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(status,
                          key: ValueKey(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: typing != null || (peer?.online ?? false) && !c.isGroup
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.55),
                          )),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          body: OrnamentBackground(
            child: Column(children: [
              const ConnectionBanner(),
              Expanded(
                child: Stack(children: [
                  ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    itemCount: msgs.length + 1,
                    itemBuilder: (context, i) {
                      if (i == msgs.length) {
                        return app.hasMore[id] == true
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                              )
                            : const SizedBox(height: 8);
                      }
                      final m = msgs[msgs.length - 1 - i];
                      final older = i + 1 < msgs.length ? msgs[msgs.length - 2 - i] : null;
                      final newer = i > 0 ? msgs[msgs.length - i] : null;
                      final newDay = older == null ||
                          !sameDay(DateTime.fromMillisecondsSinceEpoch(older.ts),
                              DateTime.fromMillisecondsSinceEpoch(m.ts));
                      final firstOfGroup = older == null ||
                          newDay ||
                          older.from != m.from ||
                          older.kind == kSystem ||
                          m.ts - older.ts > 5 * 60 * 1000;
                      final lastOfGroup = newer == null ||
                          newer.from != m.from ||
                          newer.kind == kSystem ||
                          newer.ts - m.ts > 5 * 60 * 1000 ||
                          !sameDay(DateTime.fromMillisecondsSinceEpoch(newer.ts),
                              DateTime.fromMillisecondsSinceEpoch(m.ts));
                      final animate = i == 0 && !_known.contains(m.key);
                      _known.add(m.key);
                      Widget item = m.kind == kSystem
                          ? _SystemPill(text: '${_senderName(c, m.from)}: ${L.t(m.text)}')
                          : MessageBubble(
                              key: ValueKey(m.key),
                              message: m,
                              chat: c,
                              mine: m.from == me,
                              firstOfGroup: firstOfGroup,
                              lastOfGroup: lastOfGroup,
                              replied: m.reply > 0 ? byId[m.reply] : null,
                              senderName: _senderName,
                              onLongPress: () => _menu(m),
                              onReply: () => _setReply(m),
                            );
                      if (animate) item = _NewMessageIn(fromRight: m.from == me, child: item);
                      return Column(children: [
                        if (newDay) _DayChip(text: dayLabel(m.ts)),
                        item,
                      ]);
                    },
                  ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: AnimatedScale(
                      scale: _showDown ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: FloatingActionButton.small(
                        heroTag: null,
                        onPressed: _toBottom,
                        backgroundColor: scheme.surface,
                        child: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.primary),
                      ),
                    ),
                  ),
                ]),
              ),
              _ContextBar(
                replyTo: _replyTo,
                editing: _editing,
                chat: c,
                senderName: _senderName,
                onClose: () {
                  if (_editing != null) _composerKey.currentState?.setText('');
                  setState(() {
                    _replyTo = null;
                    _editing = null;
                  });
                },
              ),
              _Composer(
                key: _composerKey,
                chatId: id,
                onSend: (text) {
                  if (_editing != null) {
                    app.editMessage(_editing!, text);
                  } else {
                    app.sendText(id, text, reply: _replyTo?.id ?? 0);
                    _toBottomSoon();
                  }
                  setState(() {
                    _replyTo = null;
                    _editing = null;
                  });
                },
                onImage: (file) {
                  app.sendImage(id, file, reply: _replyTo?.id ?? 0);
                  setState(() => _replyTo = null);
                  _toBottomSoon();
                },
                onVoice: (path, ms) {
                  app.sendVoice(id, path, ms, reply: _replyTo?.id ?? 0);
                  setState(() => _replyTo = null);
                  _toBottomSoon();
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  void _toBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.offset > 0) _toBottom();
    });
  }
}

// ------------------------------------------------------------------ small pieces

class _NewMessageIn extends StatelessWidget {
  final Widget child;
  final bool fromRight;
  const _NewMessageIn({required this.child, required this.fromRight});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset((1 - v) * (fromRight ? 40 : -40), (1 - v) * 24),
          child: Transform.scale(
            scale: 0.85 + 0.15 * v,
            alignment: fromRight ? Alignment.bottomRight : Alignment.bottomLeft,
            child: c,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _DayChip extends StatelessWidget {
  final String text;
  const _DayChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _SystemPill extends StatelessWidget {
  final String text;
  const _SystemPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: DostColors.emerald.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.primary)),
        ),
      ),
    );
  }
}

String _preview(Message m) {
  if (m.deleted) return L.t('deleted_msg');
  if (m.kind == kImage) return '📷 ${m.text.isNotEmpty ? m.text : L.t('photo')}';
  if (m.kind == kVoice) return '🎤 ${L.t('voice')}';
  return m.text;
}

/// Reply / edit preview above the composer.
class _ContextBar extends StatelessWidget {
  final Message? replyTo, editing;
  final Chat chat;
  final String Function(Chat, int) senderName;
  final VoidCallback onClose;
  const _ContextBar(
      {required this.replyTo,
      required this.editing,
      required this.chat,
      required this.senderName,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    final m = editing ?? replyTo;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: m == null
          ? const SizedBox(width: double.infinity)
          : Container(
              color: scheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(children: [
                Icon(editing != null ? Icons.edit_rounded : Icons.reply_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Container(width: 3, height: 36, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(editing != null ? L.t('editing') : senderName(chat, m.from),
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(_preview(m), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
              ]),
            ),
    );
  }
}

// ------------------------------------------------------------------ bubble

class MessageBubble extends StatefulWidget {
  final Message message;
  final Chat chat;
  final bool mine, firstOfGroup, lastOfGroup;
  final Message? replied;
  final String Function(Chat, int) senderName;
  final VoidCallback onLongPress, onReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.chat,
    required this.mine,
    required this.firstOfGroup,
    required this.lastOfGroup,
    required this.replied,
    required this.senderName,
    required this.onLongPress,
    required this.onReply,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _armed = false;
  late final AnimationController _heart =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  Message get m => widget.message;

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (m.pending || m.deleted) return;
    app.react(m, '❤️');
    _heart.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = widget.mine;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    final fg = mine ? Colors.white : scheme.onSurface;
    final meta = mine ? Colors.white.withValues(alpha: 0.75) : scheme.onSurface.withValues(alpha: 0.5);
    const r = Radius.circular(20);
    const rs = Radius.circular(6);
    final radius = BorderRadius.only(
      topLeft: !mine && !widget.firstOfGroup ? rs : r,
      bottomLeft: !mine && widget.lastOfGroup ? rs : (!mine ? rs : r),
      topRight: mine && !widget.firstOfGroup ? rs : r,
      bottomRight: mine && widget.lastOfGroup ? rs : (mine ? rs : r),
    );
    final isImage = m.kind == kImage && !m.deleted;

    // --- content
    final children = <Widget>[];
    if (widget.chat.isGroup && !mine && widget.firstOfGroup) {
      final g = DostColors.avatars[m.from % DostColors.avatars.length];
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(isImage ? 10 : 0, isImage ? 6 : 0, 0, 3),
        child: Text(widget.senderName(widget.chat, m.from),
            style: TextStyle(color: g[0], fontWeight: FontWeight.w700, fontSize: 13.5)),
      ));
    }
    if (m.reply > 0) {
      final rep = widget.replied;
      children.add(Container(
        margin: EdgeInsets.fromLTRB(isImage ? 6 : 0, isImage ? 6 : 0, isImage ? 6 : 0, 6),
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: 0.18) : scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: mine ? Colors.white : scheme.primary, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (rep != null)
            Text(widget.senderName(widget.chat, rep.from),
                style: TextStyle(
                    color: mine ? Colors.white : scheme.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
          Text(rep != null ? _preview(rep) : '…',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13.5)),
        ]),
      ));
    }

    final time = Row(mainAxisSize: MainAxisSize.min, children: [
      if (m.edited && !m.deleted)
        Text('${L.t('edited')} ', style: TextStyle(fontSize: 11, color: meta, fontStyle: FontStyle.italic)),
      Text(hhmm(m.ts), style: TextStyle(fontSize: 11, color: meta)),
      if (mine) ...[
        const SizedBox(width: 3),
        StatusIcon(
          message: m,
          chat: widget.chat,
          color: dark ? const Color(0xFF7FFFD4) : const Color(0xFFB9FFE6),
          mutedColor: meta,
          size: 15,
        ),
      ],
    ]);
    final timeW = 40.0 + (mine ? 20 : 0) + (m.edited ? 62 : 0);

    if (m.deleted) {
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 15, color: meta),
        const SizedBox(width: 6),
        Text(L.t('deleted_msg'), style: TextStyle(color: meta, fontStyle: FontStyle.italic)),
        const SizedBox(width: 10),
        time,
      ]));
    } else if (m.kind == kText) {
      children.add(Stack(children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: m.text),
            WidgetSpan(child: SizedBox(width: timeW, height: 12)),
          ]),
          style: TextStyle(color: fg, fontSize: 16, height: 1.3),
        ),
        Positioned(right: 0, bottom: 0, child: time),
      ]));
    } else if (m.kind == kImage) {
      children.add(_ImageContent(message: m, maxW: maxW));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        child: m.text.isNotEmpty
            ? Stack(children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: m.text),
                    WidgetSpan(child: SizedBox(width: timeW, height: 12)),
                  ]),
                  style: TextStyle(color: fg, fontSize: 15.5),
                ),
                Positioned(right: 0, bottom: 0, child: time),
              ])
            : Align(alignment: Alignment.centerRight, child: time),
      ));
    } else if (m.kind == kVoice) {
      children.add(VoiceBubble(message: m, mine: mine));
      children.add(Align(alignment: Alignment.centerRight, child: time));
    }
    if (m.status == stFailed) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(L.t('failed'), style: TextStyle(fontSize: 11.5, color: mine ? Colors.white : DostColors.red)),
      ));
    }

    Widget bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: isImage ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 8, 10, 7),
      decoration: BoxDecoration(
        gradient: mine
            ? const LinearGradient(
                colors: [Color(0xFF0E9B6A), Color(0xFF12A99A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
        color: mine ? null : (dark ? const Color(0xFF1B2925) : Colors.white),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: isImage ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );

    // reactions under the bubble
    if (m.rx.isNotEmpty) {
      bubble = Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bubble,
          Transform.translate(
            offset: const Offset(0, -6),
            child: Wrap(spacing: 4, children: [
              for (final e in m.rx.entries)
                GestureDetector(
                  onTap: () => app.react(m, e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: e.value.contains(app.myId)
                          ? scheme.primary.withValues(alpha: dark ? 0.45 : 0.18)
                          : (dark ? const Color(0xFF243530) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
                    child: Text('${e.key}${e.value.length > 1 ? ' ${e.value.length}' : ''}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ]),
          ),
        ],
      );
    }

    // double-tap heart burst
    bubble = Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
      bubble,
      IgnorePointer(
        child: AnimatedBuilder(
          animation: _heart,
          builder: (_, __) {
            final t = _heart.value;
            if (t == 0 || t == 1) return const SizedBox.shrink();
            final scale = t < 0.3 ? Curves.easeOutBack.transform(t / 0.3) * 1.3 : 1.3 - (t - 0.3) * 0.4;
            return Opacity(
              opacity: t < 0.7 ? 1 : (1 - t) / 0.3,
              child: Transform.scale(scale: scale, child: const Text('❤️', style: TextStyle(fontSize: 48))),
            );
          },
        ),
      ),
    ]);

    return Padding(
      padding: EdgeInsets.only(top: widget.firstOfGroup ? 8 : 2),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        onDoubleTap: _doubleTap,
        onTap: m.status == stFailed ? () => app.retry(m) : null,
        onHorizontalDragUpdate: m.pending || m.deleted
            ? null
            : (d) {
                setState(() {
                  _dx = (_dx + d.delta.dx).clamp(0.0, 80.0).toDouble();
                  if (_dx > 56 && !_armed) {
                    _armed = true;
                    HapticFeedback.selectionClick();
                  } else if (_dx < 56) {
                    _armed = false;
                  }
                });
              },
        onHorizontalDragEnd: (_) {
          if (_armed) widget.onReply();
          setState(() {
            _dx = 0;
            _armed = false;
          });
        },
        child: Stack(children: [
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Opacity(
              opacity: (_dx / 56).clamp(0.0, 1.0).toDouble(),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.reply_rounded, size: 20, color: scheme.primary),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 200 : 0),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final Message message;
  final double maxW;
  const _ImageContent({required this.message, required this.maxW});

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    final double w = (media?.w ?? 0) > 0 ? media!.w.toDouble() : 4.0;
    final double h = (media?.h ?? 0) > 0 ? media!.h.toDouble() : 3.0;
    final double width = maxW.clamp(0.0, 280.0).toDouble();
    final double height = (width * h / w).clamp(140.0, 360.0).toDouble();
    final heroTag = 'img-${message.key}';
    final local = message.localPath != null && File(message.localPath!).existsSync() ? message.localPath : null;

    Widget img;
    if (local != null) {
      img = Image.file(File(local), width: width, height: height, fit: BoxFit.cover, cacheWidth: 900);
    } else if (media != null && media.id.isNotEmpty) {
      img = _RemoteImage(mediaId: media.id, width: width, height: height, sizeBytes: media.size);
    } else {
      img = Container(width: width, height: height, color: Colors.black12);
    }

    return GestureDetector(
      onTap: () {
        if (local == null && (media == null || media.id.isEmpty)) return;
        Navigator.of(context).push(PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, __, ___) => ImageViewer(heroTag: heroTag, localPath: local, mediaId: media?.id),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        ));
      },
      child: Stack(alignment: Alignment.center, children: [
        Hero(tag: heroTag, child: img),
        if (message.pending)
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            padding: const EdgeInsets.all(14),
            child: message.status == stFailed
                ? const Icon(Icons.refresh_rounded, color: Colors.white)
                : const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
          ),
      ]),
    );
  }
}

/// Auto-loads when enabled in settings; otherwise shows size and loads on tap (saves traffic).
class _RemoteImage extends StatefulWidget {
  final String mediaId;
  final double width, height;
  final int sizeBytes;
  const _RemoteImage({required this.mediaId, required this.width, required this.height, required this.sizeBytes});

  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  bool _go = false;

  @override
  Widget build(BuildContext context) {
    if (!app.autoLoadMedia && !_go) {
      return GestureDetector(
        onTap: () => setState(() => _go = true),
        child: Container(
          width: widget.width,
          height: widget.height,
          color: Colors.black26,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.download_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text('${(widget.sizeBytes / 1024).round()} KB', style: const TextStyle(color: Colors.white)),
            ]),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: app.api.mediaUrl(widget.mediaId),
      cacheKey: widget.mediaId,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      memCacheWidth: 900,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      errorWidget: (_, __, ___) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black12,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  final String heroTag;
  final String? localPath, mediaId;
  const ImageViewer({super.key, required this.heroTag, this.localPath, this.mediaId});

  @override
  Widget build(BuildContext context) {
    final Widget img = localPath != null
        ? Image.file(File(localPath!), fit: BoxFit.contain)
        : CachedNetworkImage(imageUrl: app.api.mediaUrl(mediaId!), cacheKey: mediaId, fit: BoxFit.contain);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0).abs() > 600) Navigator.pop(context);
        },
        child: Center(
          child: InteractiveViewer(maxScale: 5, child: Hero(tag: heroTag, child: img)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ composer

class _Composer extends StatefulWidget {
  final int chatId;
  final void Function(String text) onSend;
  final void Function(XFile file) onImage;
  final void Function(String path, int ms) onVoice;
  const _Composer({super.key, required this.chatId, required this.onSend, required this.onImage, required this.onVoice});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _rec = AudioRecorder();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _recording = false;
  bool _cancelled = false;
  final _sw = Stopwatch();
  Timer? _tick;
  double _dragX = 0;

  bool get _hasText => _ctrl.text.trim().isNotEmpty;

  void focus() => _focus.requestFocus();

  void setText(String t) {
    _ctrl.text = t;
    _ctrl.selection = TextSelection.collapsed(offset: t.length);
    if (t.isNotEmpty) _focus.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    _pulse.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    if (!_hasText) return;
    HapticFeedback.lightImpact();
    widget.onSend(_ctrl.text);
    _ctrl.clear();
    setState(() {});
  }

  Future<void> _pickImage() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: _sourceTile(ctx, Icons.photo_camera_rounded, L.t('camera'), ImageSource.camera)),
            const SizedBox(width: 12),
            Expanded(child: _sourceTile(ctx, Icons.photo_library_rounded, L.t('gallery'), ImageSource.gallery)),
          ]),
        ),
      ),
    );
    if (src == null) return;
    // resize + JPEG 70%: a 4 MB photo becomes ~150 KB — fast even on slow 3G
    final f = await ImagePicker().pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
    if (f != null) widget.onImage(f);
  }

  Widget _sourceTile(BuildContext ctx, IconData icon, String label, ImageSource src) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.pop(ctx, src),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: DostColors.emerald.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Icon(icon, size: 32, color: DostColors.emerald),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Future<void> _startRec() async {
    if (!await _rec.hasPermission()) {
      if (mounted) toast(context, L.t('mic_perm'));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    // AAC 32 kbps mono ≈ 4 KB per second of speech
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050, numChannels: 1),
      path: path,
    );
    HapticFeedback.mediumImpact();
    _sw
      ..reset()
      ..start();
    _cancelled = false;
    _dragX = 0;
    _pulse.repeat(reverse: true);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
      app.sendTyping(widget.chatId, recording: true);
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRec() async {
    if (!_recording) return;
    _tick?.cancel();
    _pulse.stop();
    _sw.stop();
    final ms = _sw.elapsedMilliseconds;
    setState(() => _recording = false);
    if (_cancelled || ms < 700) {
      await _rec.cancel();
      HapticFeedback.lightImpact();
      return;
    }
    final path = await _rec.stop();
    if (path != null) {
      HapticFeedback.lightImpact();
      widget.onVoice(path, ms);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: scheme.surface,
      padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + MediaQuery.paddingOf(context).bottom * 0.6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (!_recording)
          IconButton(
            onPressed: _pickImage,
            icon: Icon(Icons.add_photo_alternate_rounded, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        Expanded(
          child: _recording
              ? Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    FadeTransition(
                      opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse),
                      child: const Icon(Icons.fiber_manual_record_rounded, color: DostColors.red, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(duration(_sw.elapsedMilliseconds),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Opacity(
                      opacity: (1 + _dragX / 120).clamp(0.2, 1.0).toDouble(),
                      child: Transform.translate(
                        offset: Offset(_dragX * 0.5, 0),
                        child: Text(L.t('slide_cancel'),
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55))),
                      ),
                    ),
                  ]),
                )
              : TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: L.t('message_hint'),
                    fillColor: dark ? const Color(0xFF16231F) : const Color(0xFFF0F4F2),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    if (_hasText) app.sendTyping(widget.chatId);
                  },
                ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _hasText ? _send : () => toast(context, L.t('hold_to_record')),
          onLongPressStart: _hasText ? null : (_) => _startRec(),
          onLongPressMoveUpdate: _hasText
              ? null
              : (d) {
                  setState(() => _dragX = d.offsetFromOrigin.dx.clamp(-160.0, 0.0).toDouble());
                  if (d.offsetFromOrigin.dx < -110 && !_cancelled) {
                    _cancelled = true;
                    HapticFeedback.heavyImpact();
                    _stopRec();
                  }
                },
          onLongPressEnd: _hasText ? null : (_) => _stopRec(),
          child: AnimatedScale(
            scale: _recording ? 1.35 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: _recording ? null : DostColors.brand,
                color: _recording ? DostColors.red : null,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: (_recording ? DostColors.red : DostColors.emerald).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (c, a) => RotationTransition(
                  turns: Tween(begin: 0.75, end: 1.0).animate(a),
                  child: ScaleTransition(scale: a, child: c),
                ),
                child: Icon(
                  _hasText ? Icons.send_rounded : Icons.mic_rounded,
                  key: ValueKey(_hasText),
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
