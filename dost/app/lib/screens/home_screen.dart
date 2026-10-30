import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final unread = app.totalUnread;
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [ChatsTab(), ContactsTab(), SettingsTab()]),
      floatingActionButton: _tab == 0
          ? GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                showNewChatSheet(context);
              },
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: DostColors.brand,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: DostColors.emerald.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              backgroundColor: DostColors.emerald,
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: L.t('chats'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline_rounded),
            selectedIcon: const Icon(Icons.people_rounded),
            label: L.t('contacts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: L.t('settings'),
          ),
        ],
      ),
    );
  }
}

void openChat(BuildContext context, Chat c) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
}

void showNewChatSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
            title: Text(L.t('new_chat')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PickContactScreen()));
            },
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.group_add_rounded)),
            title: Text(L.t('new_group')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewGroupScreen()));
            },
          ),
        ]),
      ),
    ),
  );
}

// ------------------------------------------------------------------ chats tab

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        var list = app.sortedChats;
        if (_q.isNotEmpty) {
          final q = _q.toLowerCase();
          list = list.where((c) => c.displayTitle(app.myId).toLowerCase().contains(q)).toList();
        }
        return CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 108,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 14),
              title: ShaderMask(
                shaderCallback: (r) => DostColors.brand.createShader(r),
                child: const Text('Dost',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: ConnectionBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: L.t('search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _q.isNotEmpty ? const SizedBox() : const _EmptyChats(),
            )
          else
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => Appear(
                key: ValueKey(list[i].id),
                delayMs: i < 10 ? i * 30 : 0,
                child: ChatTile(chat: list[i]),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ]);
      },
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.elasticOut,
          builder: (_, v, c) => Transform.scale(scale: v, child: c),
          child: const Text('💬', style: TextStyle(fontSize: 72)),
        ),
        const SizedBox(height: 16),
        Text(L.t('no_chats'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(L.t('no_chats_sub'), textAlign: TextAlign.center, style: TextStyle(color: muted)),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: () => showNewChatSheet(context),
          icon: const Icon(Icons.add_comment_rounded),
          label: Text(L.t('start_chat')),
        ),
      ]),
    );
  }
}

class ChatTile extends StatelessWidget {
  final Chat chat;
  const ChatTile({super.key, required this.chat});

  String _preview(Message m) {
    if (m.deleted) return L.t('deleted_msg');
    switch (m.kind) {
      case kImage:
        return '📷 ${m.text.isNotEmpty ? m.text : L.t('photo')}';
      case kVoice:
        return '🎤 ${L.t('voice')} ${duration(m.media?.dur ?? 0)}';
      case kSystem:
        return L.t(m.text);
    }
    return m.text;
  }

  @override
  Widget build(BuildContext context) {
    final me = app.myId;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    final last = chat.last;
    final typing = app.typingText(chat.id);
    final peer = chat.peer(me);
    final unread = chat.unread > 0;

    Widget subtitle;
    if (typing != null) {
      subtitle = Row(children: [
        Text(typing, style: TextStyle(color: scheme.primary, fontStyle: FontStyle.italic)),
        const SizedBox(width: 4),
        TypingDots(color: scheme.primary, size: 4),
      ]);
    } else if (last != null) {
      final mine = last.from == me;
      final who = mine
          ? '${L.t('you')}: '
          : (chat.isGroup && last.kind != kSystem ? '${chat.member(last.from)?.name ?? ''}: ' : '');
      subtitle = Text.rich(
        TextSpan(children: [
          if (who.isNotEmpty) TextSpan(text: who, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.8))),
          TextSpan(text: _preview(last)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: muted, fontSize: 14.5),
      );
    } else {
      subtitle = Text(L.t('write_first'), style: TextStyle(color: muted));
    }

    Widget? status;
    if (last != null && last.from == me && last.kind != kSystem) {
      status = Padding(
        padding: const EdgeInsets.only(right: 4),
        child: StatusIcon(message: last, chat: chat, color: scheme.primary, mutedColor: muted),
      );
    }

    return InkWell(
      onTap: () => openChat(context, chat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Hero(
            tag: 'avatar-${chat.id}',
            child: Avatar(
              id: chat.isGroup ? chat.id : (peer?.id ?? chat.id),
              name: chat.displayTitle(me),
              mediaId: chat.displayAvatar(me),
              size: 56,
              online: !chat.isGroup && (peer?.online ?? false),
              group: chat.isGroup,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(chat.displayTitle(me),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                ),
                if (chat.muted) Icon(Icons.volume_off_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                if (status != null) status,
                Text(shortTime(chat.sortTs),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: unread ? scheme.primary : muted,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.normal)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: subtitle),
                AnimatedScale(
                  scale: unread ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: chat.muted ? null : DostColors.brand,
                      color: chat.muted ? muted : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(chat.unread > 999 ? '999+' : '${chat.unread}',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// clock (sending) · ✓ (sent) · ✓✓ (read) · ! (failed)
class StatusIcon extends StatelessWidget {
  final Message message;
  final Chat chat;
  final Color color, mutedColor;
  final double size;
  const StatusIcon(
      {super.key,
      required this.message,
      required this.chat,
      required this.color,
      required this.mutedColor,
      this.size = 16});

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    if (message.status == stFailed) {
      icon = Icon(Icons.error_rounded, key: const ValueKey('f'), size: size, color: DostColors.red);
    } else if (message.pending) {
      icon = Icon(Icons.schedule_rounded, key: const ValueKey('p'), size: size - 2, color: mutedColor);
    } else if (chat.othersRead(app.myId) >= message.id) {
      icon = Icon(Icons.done_all_rounded, key: const ValueKey('r'), size: size, color: color);
    } else {
      icon = Icon(Icons.done_rounded, key: const ValueKey('s'), size: size, color: mutedColor);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: icon,
    );
  }
}
