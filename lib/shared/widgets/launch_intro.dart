import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// The mascot says hello, then opens a window onto the app.
///
/// It takes over from the native splash, which shows this very first frame —
/// coral, the face, the same size in the same place — so the handoff cannot
/// be seen. Then: a squash-and-stretch bounce, a blink, sound waves rippling
/// out, the little voice bars dancing, the name rising in, and a circle
/// opening out of the face to reveal Home, which has been loading underneath
/// the whole time.
///
/// About a second and a half, once per launch. Removes itself when done.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key});

  /// Width of the mascot's face on the native splash, in logical pixels.
  /// See tool/render_splash_test.dart: 358px of a 1152px icon drawn at 288dp.
  static const double faceWidth = 89.5;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1750);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _duration)
        ..forward().whenComplete(() {
          if (mounted) setState(() => _done = true);
        });

  bool _done = false;

  /// A slice of the timeline, 0→1 over [begin]–[end] of the whole.
  Animation<double> _phase(
    double begin,
    double end, [
    Curve curve = Curves.linear,
  ]) => CurvedAnimation(
    parent: _c,
    curve: Interval(begin, end, curve: curve),
  );

  late final _bounce = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.16,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.16,
        end: 0.94,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.94,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
  ]).animate(_phase(0.0, 0.3));

  late final _waves = _phase(0.08, 0.62);
  late final _blink = _phase(0.26, 0.36);
  // The native splash already shows the rays, so they start drawn and pop.
  late final _rays = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.45,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.45,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 60,
    ),
  ]).animate(_phase(0.12, 0.5));
  late final _title = _phase(0.26, 0.5, Curves.easeOutCubic);
  late final _tagline = _phase(0.36, 0.58, Curves.easeOutCubic);
  late final _reveal = _phase(0.66, 1.0, Curves.easeInCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // The intro sits above the Navigator, outside any page, so it brings
      // its own Material for the app's text style — without one, text falls
      // back to Flutter's underlined debug look.
      child: Material(
        type: MaterialType.transparency,
        // Nothing underneath can be tapped until the window has opened.
        child: AbsorbPointer(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final size = MediaQuery.sizeOf(context);
              final center = size.center(Offset.zero);
              // Far enough to clear every corner.
              final maxRadius = size.longestSide;
              final hole = _reveal.value * maxRadius;

              return ClipPath(
                clipper: _HoleClipper(center: center, radius: hole),
                child: Container(
                  color: AppColors.primary,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _WavesPainter(
                            center: center,
                            progress: _waves.value,
                            faceWidth: LaunchIntro.faceWidth,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Transform.scale(
                            // Grows away as the window opens through it.
                            scale: _bounce.value * (1 + _reveal.value * 1.6),
                            child: Opacity(
                              opacity: (1 - _reveal.value * 1.4).clamp(
                                0.0,
                                1.0,
                              ),
                              child: CustomPaint(
                                size: const Size.square(
                                  LaunchIntro.faceWidth * 1.6,
                                ),
                                painter: _FacePainter(
                                  faceWidth: LaunchIntro.faceWidth,
                                  blink: _blink.value,
                                  rays: _rays.value,
                                  // Voice bars keep talking throughout.
                                  talk: _c.value,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: center.dy + LaunchIntro.faceWidth * 0.9,
                        child: Opacity(
                          opacity: (1 - _reveal.value * 2).clamp(0.0, 1.0),
                          child: Column(
                            children: [
                              _Rise(
                                progress: _title.value,
                                child: const Text(
                                  'Lecto',
                                  style: TextStyle(
                                    color: AppColors.textOnPrimary,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.2,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _Rise(
                                progress: _tagline.value,
                                child: Text(
                                  'Never miss a word.',
                                  style: TextStyle(
                                    color: AppColors.textOnPrimary.withValues(
                                      alpha: 0.85,
                                    ),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Slides up into place while fading in.
class _Rise extends StatelessWidget {
  final double progress;
  final Widget child;

  const _Rise({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 18),
        child: child,
      ),
    );
  }
}

/// Everything but a growing circle: the window through to the app.
class _HoleClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  const _HoleClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) {
    final whole = Path()..addRect(Offset.zero & size);
    if (radius <= 0) return whole;
    return Path.combine(
      PathOperation.difference,
      whole,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldReclip(_HoleClipper old) =>
      old.radius != radius || old.center != center;
}

/// Three rings of sound spreading out from the face.
class _WavesPainter extends CustomPainter {
  final Offset center;
  final double progress;
  final double faceWidth;

  const _WavesPainter({
    required this.center,
    required this.progress,
    required this.faceWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    for (var i = 0; i < 3; i++) {
      // Staggered: each ring leaves a little after the one before.
      final t = ((progress - i * 0.16) / 0.68).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final radius = faceWidth * (0.7 + t * 2.4);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - t) + 1
        ..color = Colors.white.withValues(alpha: 0.45 * (1 - t));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.progress != progress;
}

/// The mascot, drawn in parts so each can move.
///
/// Coordinates follow the mascot's own 400-unit artwork (the face body is
/// 224 units wide), scaled so that body is [faceWidth] across.
class _FacePainter extends CustomPainter {
  final double faceWidth;

  /// 0→1 over one blink; eyes are shut at 0.5.
  final double blink;

  /// Size of the sparkle rays; 1 is as drawn.
  final double rays;

  /// Drives the voice bars.
  final double talk;

  const _FacePainter({
    required this.faceWidth,
    required this.blink,
    required this.rays,
    required this.talk,
  });

  static const _ink = Color(0xFF201A18);
  static const _body = Color(0xFFFFF8FA);
  static const _cheek = Color(0x99FFAF99);
  static const _voice = Color(0xFFF96D38);
  static const _ray = Color(0xFFFFE175);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = faceWidth / 224;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);
    // Face centre in artwork units.
    canvas.translate(-200, -212);

    // Sparkle rays, popping out from the corner.
    if (rays > 0) {
      final ray = Paint()
        ..color = _ray
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round;
      final grow = rays.clamp(0.0, 1.6);
      canvas.save();
      canvas.translate(300, 106);
      canvas.scale(grow);
      canvas.translate(-300, -106);
      canvas.drawLine(const Offset(294, 100), const Offset(316, 68), ray);
      canvas.drawLine(const Offset(324, 114), const Offset(356, 108), ray);
      canvas.drawCircle(const Offset(350, 70), 6, Paint()..color = _ray);
      canvas.restore();
    }

    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(88, 104, 224, 216),
        const Radius.circular(72),
      ),
      Paint()..color = _body,
    );

    // Eyes: squeeze shut at the middle of a blink.
    final open = 1 - math.sin(blink.clamp(0.0, 1.0) * math.pi) * 0.9;
    for (final x in const [156.0, 244.0]) {
      canvas.save();
      canvas.translate(x, 190);
      canvas.scale(1, open);
      canvas.drawCircle(Offset.zero, 18, Paint()..color = _ink);
      if (open > 0.5) {
        canvas.drawCircle(
          const Offset(7, -7),
          6,
          Paint()..color = Colors.white,
        );
      }
      canvas.restore();
    }

    // Cheeks.
    for (final x in const [136.0, 264.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 218), width: 28, height: 16),
        Paint()..color = _cheek,
      );
    }

    // Smile.
    canvas.drawPath(
      Path()
        ..moveTo(176, 228)
        ..cubicTo(185, 244, 215, 244, 224, 228),
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round,
    );

    // Voice bars, bobbing out of step with each other.
    final voice = Paint()..color = _voice;
    double wave(double phase) =>
        0.55 + 0.45 * math.sin(talk * math.pi * 7 + phase).abs();
    final left = 18 * wave(0);
    final middle = 28 * wave(1.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(188.5, 281),
          width: 7,
          height: left,
        ),
        const Radius.circular(3.5),
      ),
      voice,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(200.5, 279),
          width: 7,
          height: middle,
        ),
        const Radius.circular(3.5),
      ),
      voice,
    );
    canvas.drawCircle(const Offset(215, 279), 4.5 * wave(2.1), voice);
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.blink != blink || old.rays != rays || old.talk != talk;
}
