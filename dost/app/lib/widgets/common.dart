import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/fmt.dart';
import '../core/l10n.dart';
import '../core/theme.dart';

/// Round avatar: photo if set, otherwise gradient with initials. Green dot when online.
class Avatar extends StatelessWidget {
  final int id;
  final String name;
  final String mediaId;
  final double size;
  final bool online;
  final bool group;

  const Avatar({
    super.key,
    required this.id,
    required this.name,
    this.mediaId = '',
    this.size = 48,
    this.online = false,
    this.group = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = DostColors.avatars[id.abs() % DostColors.avatars.length];
    final Widget face = mediaId.isNotEmpty
        ? ClipOval(
            child: CachedNetworkImage(
              imageUrl: app.api.mediaUrl(mediaId),
              cacheKey: mediaId,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: (size * 3).round(),
              placeholder: (_, __) => _gradient(g),
              errorWidget: (_, __, ___) => _gradient(g),
            ),
          )
        : _gradient(g);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        face,
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2.5),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _gradient(List<Color> g) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        alignment: Alignment.center,
        child: group && name.isEmpty
            ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.5)
            : Text(
                initials(name),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36),
              ),
      );
}

/// The Dost logo: gradient squircle with a speech bubble and a gold star.
class DostLogo extends StatelessWidget {
  final double size;
  const DostLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: DostColors.brand,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: DostColors.emerald.withValues(alpha: 0.4),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: Stack(alignment: Alignment.center, children: [
        Icon(Icons.chat_bubble_rounded, color: Colors.white, size: size * 0.58),
        Padding(
          padding: EdgeInsets.only(bottom: size * 0.06),
          child: Text('D',
              style: TextStyle(
                  color: DostColors.emerald, fontWeight: FontWeight.w900, fontSize: size * 0.28)),
        ),
        Positioned(
          right: size * 0.14,
          top: size * 0.12,
          child: Icon(Icons.star_rounded, color: DostColors.gold, size: size * 0.2),
        ),
      ]),
    );
  }
}

/// Subtle Turkmen carpet "göl" ornament for chat backgrounds.
class OrnamentPainter extends CustomPainter {
  final Color color;
  OrnamentPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const step = 72.0;
    for (var y = -step / 2; y < size.height + step; y += step) {
      final row = (y / step).round();
      for (var x = (row.isEven ? 0.0 : step / 2) - step / 2; x < size.width + step; x += step) {
        _gol(canvas, Offset(x, y), 18, p);
      }
    }
  }

  void _gol(Canvas c, Offset o, double r, Paint p) {
    final oct = Path();
    for (var i = 0; i < 8; i++) {
      final a = math.pi / 8 + i * math.pi / 4;
      final pt = o + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        oct.moveTo(pt.dx, pt.dy);
      } else {
        oct.lineTo(pt.dx, pt.dy);
      }
    }
    oct.close();
    c.drawPath(oct, p);
    final d = r * 0.45;
    final diamond = Path()
      ..moveTo(o.dx, o.dy - d)
      ..lineTo(o.dx + d, o.dy)
      ..lineTo(o.dx, o.dy + d)
      ..lineTo(o.dx - d, o.dy)
      ..close();
    c.drawPath(diamond, p);
    c.drawCircle(o, 1.8, p..style = PaintingStyle.fill);
    p.style = PaintingStyle.stroke;
  }

  @override
  bool shouldRepaint(OrnamentPainter old) => old.color != color;
}

class OrnamentBackground extends StatelessWidget {
  final Widget child;
  const OrnamentBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0A1714), Color(0xFF07100E)]
              : const [Color(0xFFE9F4EF), Color(0xFFF4F1E8)],
        ),
      ),
      child: CustomPaint(
        painter: OrnamentPainter(
            (dark ? Colors.white : DostColors.emerald).withValues(alpha: dark ? 0.035 : 0.06)),
        child: child,
      ),
    );
  }
}

/// Big gradient button with press animation and haptics.
class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const GradientButton({super.key, required this.label, this.onTap, this.loading = false});

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: enabled || widget.loading ? 1 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 56,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: DostColors.brand,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: DostColors.emerald.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: widget.loading
                ? const SizedBox(
                    width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(widget.label,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Three bouncing dots — "typing…"
class TypingDots extends StatefulWidget {
  final Color color;
  final double size;
  const TypingDots({super.key, required this.color, this.size = 6});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_c.value - i * 0.2) % 1.0;
          final double dy = -math.sin(t * math.pi).clamp(0.0, 1.0).toDouble() * widget.size * 0.8;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.size * 0.25),
            child: Transform.translate(
              offset: Offset(0, t < 0.5 ? dy : 0.0),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Thin banner under the app bar when the network is down.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final show = app.net != NetState.online;
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: app.net == NetState.connecting
                      ? DostColors.gold.withValues(alpha: 0.9)
                      : const Color(0xFF64748B),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                        width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 8),
                    Text(L.t(app.net == NetState.connecting ? 'connecting' : 'offline'),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
        );
      },
    );
  }
}

/// Fade + slide in once when first built.
class Appear extends StatelessWidget {
  final Widget child;
  final int delayMs;
  const Appear({super.key, required this.child, this.delayMs = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: c),
      ),
      child: child,
    );
  }
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: const Duration(seconds: 2),
    ));
}

String errorText(Object e) {
  final s = e.toString();
  for (final k in ['bad_code', 'code_expired', 'too_many', 'wait', 'bad_phone', 'not_found']) {
    if (s.contains(k)) return L.t(k);
  }
  if (s.contains('SocketException') || s.contains('TimeoutException') || s.contains('ClientException')) {
    return L.t('network_error');
  }
  return L.t('error');
}
