import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Lets a tester send feedback back through whatever app they prefer.
///
/// The app has no network permission and no server, so feedback cannot be
/// posted anywhere. Instead it opens the share sheet with a message already
/// written, which the tester sends by WhatsApp, email or anything else.
class FeedbackService {
  /// Share a pre-written note, with the details that make a bug reproducible.
  ///
  /// [recordingCount] and [awaitingCount] say how much the tester has actually
  /// used the app, which separates "tried it once" from "used it all term".
  static Future<void> send({
    required String appVersion,
    int? recordingCount,
    int? awaitingCount,
  }) async {
    final buffer = StringBuffer()
      ..writeln('My Lecto feedback')
      ..writeln()
      ..writeln('What I was doing:')
      ..writeln()
      ..writeln('What happened:')
      ..writeln()
      ..writeln('What I expected:')
      ..writeln()
      ..writeln('---')
      ..writeln('App version: $appVersion')
      ..writeln('Android: ${_androidVersion()}')
      ..writeln('Device: ${_deviceLabel()}');

    if (recordingCount != null) {
      buffer.writeln('Recordings: $recordingCount'
          '${awaitingCount != null ? ' ($awaitingCount without notes)' : ''}');
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: buffer.toString(),
          subject: 'My Lecto feedback',
        ),
      );
    } catch (e) {
      debugPrint('Feedback: could not open the share sheet: $e');
      rethrow;
    }
  }

  static String _androidVersion() {
    if (!Platform.isAndroid) return Platform.operatingSystem;
    // operatingSystemVersion is verbose but needs no extra dependency.
    final raw = Platform.operatingSystemVersion;
    final api = RegExp(r'API level (\d+)').firstMatch(raw)?.group(1);
    return api == null ? raw : 'API $api';
  }

  static String _deviceLabel() {
    final raw = Platform.operatingSystemVersion;
    final model = RegExp(r"on '([^']+)'").firstMatch(raw)?.group(1);
    return model ?? 'unknown';
  }
}
