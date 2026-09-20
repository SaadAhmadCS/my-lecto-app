import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/errors/error_messages.dart';

void main() {
  test('a full disk says so, because the user can act on it', () {
    final full = FileSystemException(
      'Cannot write',
      '/audio/chunk_000.m4a',
      const OSError('No space left on device', 28),
    );

    expect(ErrorMessages.from(full), contains('out of storage'));
  });

  test('a missing file is named as missing, not as a generic failure', () {
    final gone = FileSystemException(
      'Cannot open',
      '/audio/chunk_000.m4a',
      const OSError('No such file or directory', 2),
    );

    expect(ErrorMessages.from(gone), contains('no longer on this device'));
  });

  test('a failed merge is explained', () {
    expect(
      ErrorMessages.from(PlatformException(code: 'merge_failed')),
      contains('join the audio'),
    );
  });

  test('raw exception text never reaches the user', () {
    final ugly = Exception('SqfliteDatabaseException(near "SELECT": syntax)');

    final message = ErrorMessages.from(ugly, action: 'open this recording');
    expect(message, isNot(contains('Sqflite')));
    expect(message, isNot(contains('SELECT')));
    expect(message, 'Couldn\'t open this recording. Please try again.');
  });

  test('without an action it falls back to something generic', () {
    expect(ErrorMessages.from(Exception('boom')), ErrorMessages.generic);
  });

  test('a timeout is named rather than swallowed', () {
    expect(
      ErrorMessages.from(TimeoutException('too slow')),
      contains('took too long'),
    );
  });
}
