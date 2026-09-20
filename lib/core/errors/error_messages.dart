import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Turns exceptions into sentences a person can act on.
///
/// Raw exception text never reaches the UI; it goes to the log.
class ErrorMessages {
  ErrorMessages._();

  static const generic = 'Something went wrong. Please try again.';

  /// [action] names what failed, e.g. "rename the recording", and is used
  /// when the error itself says nothing more useful.
  static String from(Object error, {String? action}) {
    debugPrint('Error${action == null ? '' : ' ($action)'}: $error');
    final fallback =
        action == null ? generic : 'Couldn\'t $action. Please try again.';

    return switch (error) {
      // Nothing here talks to a server, but file and storage work still
      // fails in ways worth naming.
      FileSystemException() => _file(error) ?? fallback,
      TimeoutException() => 'That took too long. Please try again.',
      PlatformException(:final code) => _platform(code) ?? fallback,
      _ => fallback,
    };
  }

  static String? _file(FileSystemException e) {
    final message = e.osError?.message.toLowerCase() ?? '';
    if (message.contains('no space')) {
      return 'Your device is out of storage. Free up some space and try again.';
    }
    if (message.contains('permission')) {
      return 'Lecto doesn\'t have permission to use that file.';
    }
    if (e.osError?.errorCode == 2 || message.contains('no such file')) {
      return 'That file is no longer on this device.';
    }
    return null;
  }

  static String? _platform(String code) => switch (code) {
        'merge_failed' => 'Couldn\'t join the audio for this recording.',
        'bad_args' => generic,
        _ => null,
      };
}
