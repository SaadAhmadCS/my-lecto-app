// Renders the launch-screen mascot PNGs from vector art.
//
// Run with: flutter test tool/render_splash_test.dart
// Then:     dart run flutter_native_splash:create
//
// Android 12+ shows a 1152px splash icon but masks it to the centre circle
// (768px), so the face is drawn small and centred to survive the mask. The
// same face, at the size the animated intro starts from, keeps the handoff
// from native splash to Flutter seamless.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mascot's face with no background disc: the splash is already coral.
const _face = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="38 50 324 324" fill="none">
  <path d="M294 100L316 68" stroke="#FFE175" stroke-width="12" stroke-linecap="round"/>
  <path d="M324 114L356 108" stroke="#FFE175" stroke-width="12" stroke-linecap="round"/>
  <circle cx="350" cy="70" r="6" fill="#FFE175"/>
  <rect x="88" y="104" width="224" height="216" rx="72" fill="#FFF8FA"/>
  <circle cx="156" cy="190" r="18" fill="#201A18"/>
  <circle cx="163" cy="183" r="6" fill="#FFFFFF"/>
  <circle cx="244" cy="190" r="18" fill="#201A18"/>
  <circle cx="251" cy="183" r="6" fill="#FFFFFF"/>
  <ellipse cx="136" cy="218" rx="14" ry="8" fill="#FFAF99" opacity="0.6"/>
  <ellipse cx="264" cy="218" rx="14" ry="8" fill="#FFAF99" opacity="0.6"/>
  <path d="M176 228C185 244 215 244 224 228" stroke="#201A18" stroke-width="11" stroke-linecap="round"/>
  <rect x="185" y="272" width="7" height="18" rx="3.5" fill="#F96D38"/>
  <rect x="197" y="265" width="7" height="28" rx="3.5" fill="#F96D38"/>
  <circle cx="215" cy="279" r="4.5" fill="#F96D38"/>
</svg>
''';

Future<void> _render(
  WidgetTester tester, {
  required String path,
  required double canvas,
  required double faceWidth,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: canvas,
            height: canvas,
            child: Center(
              child: SvgPicture.string(_face, width: faceWidth),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    // Let the SVG decode before capturing.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render splash mascots', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Android 12+: 1152px canvas, 768px visible circle.
    await _render(
      tester,
      path: 'assets/branding/splash_mascot_android12.png',
      canvas: 1152,
      faceWidth: 520,
    );
    // Older Android: drawn at its own size, read as xxxhdpi (4x).
    await _render(
      tester,
      path: 'assets/branding/splash_mascot.png',
      canvas: 640,
      faceWidth: 520,
    );
  });
}
