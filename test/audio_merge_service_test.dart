import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/core/services/audio_merge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.lecto.lecto/audio');
  late Directory root;
  final calls = <MethodCall>[];

  Future<File> writeChunk(String name, [String body = 'audio']) async {
    final file = File('${root.path}/$name');
    await file.create(recursive: true);
    await file.writeAsString(body);
    return file;
  }

  /// Stands in for the native merger, writing a file the way it would.
  void handleMerge({bool fail = false, bool writeOutput = true}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (fail) {
        throw PlatformException(code: 'merge_failed', message: 'nope');
      }
      final output = call.arguments['output'] as String;
      if (writeOutput) {
        final file = File(output);
        await file.create(recursive: true);
        await file.writeAsString('merged');
      }
      return output;
    });
  }

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lecto_merge_test');
    calls.clear();

    // The service caches merges under the temp directory, which has no
    // implementation in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getTemporaryDirectory') return root.path;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(pathProvider, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('no audio returns null', () async {
    handleMerge();

    final merged = await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: const [],
    );

    expect(merged, isNull);
    expect(calls, isEmpty);
  });

  test('missing files are ignored', () async {
    handleMerge();

    final merged = await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: ['${root.path}/gone.m4a'],
    );

    expect(merged, isNull);
  });

  test('a single chunk is returned without merging', () async {
    // Nothing to join, so the native call is pointless work.
    handleMerge();
    final only = await writeChunk('chunk_000.m4a');

    final merged = await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [only.path],
    );

    expect(merged?.path, only.path);
    expect(calls, isEmpty);
  });

  test('several chunks are merged in order', () async {
    handleMerge();
    final a = await writeChunk('chunk_000.m4a');
    final b = await writeChunk('chunk_001.m4a');

    final merged = await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path],
    );

    expect(merged, isNotNull);
    expect(calls.single.method, 'mergeChunks');
    expect(calls.single.arguments['inputs'], [a.path, b.path]);
  });

  test('a failed merge returns null so the caller can fall back', () async {
    // Sharing the chunks separately still works for a short lecture.
    handleMerge(fail: true);
    final a = await writeChunk('chunk_000.m4a');
    final b = await writeChunk('chunk_001.m4a');

    final merged = await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path],
    );

    expect(merged, isNull);
  });

  test('a merge that produced nothing is treated as a failure', () async {
    handleMerge(writeOutput: false);
    final a = await writeChunk('chunk_000.m4a');
    final b = await writeChunk('chunk_001.m4a');

    final merged = await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path],
    );

    expect(merged, isNull);
  });

  test('re-sharing the same chunks reuses the merge', () async {
    handleMerge();
    final a = await writeChunk('chunk_000.m4a');
    final b = await writeChunk('chunk_001.m4a');

    await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path],
    );
    await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path],
    );

    expect(calls, hasLength(1), reason: 'second share should reuse the file');
  });

  test('a recording that gained a chunk is merged again', () async {
    // Otherwise a lecture resumed after a crash would share a stale file
    // missing its final chunks.
    handleMerge();
    final a = await writeChunk('chunk_000.m4a');
    final b = await writeChunk('chunk_001.m4a');
    final c = await writeChunk('chunk_002.m4a');

    await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path],
    );
    await AudioMergeService.mergeForSharing(
      recordingId: 'rec-1',
      chunkPaths: [a.path, b.path, c.path],
    );

    expect(calls, hasLength(2));
  });
}
