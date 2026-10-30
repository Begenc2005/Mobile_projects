import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../core/models.dart';

/// One shared player for all voice messages. Files are downloaded once and cached,
/// so replaying never uses traffic again.
class VoicePlayer extends ChangeNotifier {
  static final VoicePlayer i = VoicePlayer._();

  final AudioPlayer _p = AudioPlayer();
  String? current;
  Duration position = Duration.zero;
  bool loading = false;

  VoicePlayer._() {
    _p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _p.pause();
        _p.seek(Duration.zero);
        current = null;
        position = Duration.zero;
      }
      notifyListeners();
    });
    _p.positionStream.listen((pos) {
      if (current != null) {
        position = pos;
        notifyListeners();
      }
    });
  }

  bool isCurrent(Message m) => current == m.key;
  bool isPlaying(Message m) => current == m.key && _p.playing;

  Future<void> toggle(Message m) async {
    if (current == m.key) {
      if (_p.playing) {
        await _p.pause();
      } else {
        _p.play();
      }
      notifyListeners();
      return;
    }
    await _p.pause();
    current = m.key;
    position = Duration.zero;
    loading = true;
    notifyListeners();
    try {
      var path = m.localPath;
      if (path == null || !File(path).existsSync()) {
        final f = await app.voiceFile(m.media!.id);
        if (!f.existsSync()) await app.api.download(m.media!.id, f);
        path = f.path;
      }
      await _p.setFilePath(path);
      loading = false;
      notifyListeners();
      _p.play(); // not awaited: completes only when playback ends
    } catch (_) {
      loading = false;
      current = null;
      notifyListeners();
    }
  }

  Future<void> seekFraction(Message m, double f) async {
    if (current != m.key) return;
    final d = _p.duration ?? Duration(milliseconds: m.media?.dur ?? 0);
    await _p.seek(d * f.clamp(0.0, 1.0).toDouble());
  }
}

class VoiceBubble extends StatelessWidget {
  final Message message;
  final bool mine;
  const VoiceBubble({super.key, required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = mine ? Colors.white : scheme.primary;
    final faint = mine ? Colors.white.withValues(alpha: 0.4) : scheme.onSurface.withValues(alpha: 0.2);
    final durMs = message.media?.dur ?? 0;
    // stable pseudo-waveform from the message id
    final rnd = math.Random(message.cid.hashCode);
    final bars = List.generate(28, (_) => 0.25 + rnd.nextDouble() * 0.75);

    return ListenableBuilder(
      listenable: VoicePlayer.i,
      builder: (context, _) {
        final p = VoicePlayer.i;
        final cur = p.isCurrent(message);
        final playing = p.isPlaying(message);
        final double progress =
            cur && durMs > 0 ? (p.position.inMilliseconds / durMs).clamp(0.0, 1.0).toDouble() : 0.0;
        return SizedBox(
          width: 230,
          child: Row(children: [
            GestureDetector(
              onTap: message.media?.id.isEmpty ?? true ? null : () => p.toggle(message),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: mine ? Colors.white.withValues(alpha: 0.22) : scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: cur && p.loading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(playing), color: fg, size: 28),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    onTapDown: (d) => p.seekFraction(message, d.localPosition.dx / c.maxWidth),
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (var i = 0; i < bars.length; i++)
                            Expanded(
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 3,
                                  height: 26 * bars[i],
                                  decoration: BoxDecoration(
                                    color: (i / bars.length) <= progress && cur ? fg : faint,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cur ? duration(p.position.inMilliseconds) : duration(durMs),
                  style: TextStyle(
                      fontSize: 11.5,
                      color: mine ? Colors.white70 : scheme.onSurface.withValues(alpha: 0.55)),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
