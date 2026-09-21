import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Joins a recording's chunks into one file for sharing.
///
/// Recording in chunks protects against a crash costing the whole lecture, but
/// AI apps take a limited number of files per chat — Gemini takes 10 — and
/// discard the rest without saying so. Merging means a lecture always arrives
/// as one file no matter how long it ran.
///
/// The work happens natively with MediaMuxer, copying the encoded samples
/// across without re-encoding, so it is quick and loses no quality.
class AudioMergeService {
  static const MethodChannel _channel = MethodChannel('com.lecto.lecto/audio');

  /// Where merged files are cached, so re-sharing a lecture does not redo it.
  static const String _cacheDirName = 'merged_audio';

  /// Merge [chunkPaths] in order and return the single file.
  ///
  /// Returns null when merging is unavailable or fails — callers fall back to
  /// sharing the chunks themselves. A single chunk needs no merging and is
  /// returned as-is.
  static Future<File?> mergeForSharing({
    required String recordingId,
    required List<String> chunkPaths,
  }) async {
    final existing = <String>[];
    for (final path in chunkPaths) {
      if (await File(path).exists()) existing.add(path);
    }

    if (existing.isEmpty) return null;
    if (existing.length == 1) return File(existing.first);

    try {
      final output = await _outputFile(recordingId, existing);

      // Reuse an earlier merge of exactly these chunks.
      if (await output.exists() && await output.length() > 0) {
        debugPrint('AudioMerge: reusing ${output.path}');
        return output;
      }

      final merged = await _channel.invokeMethod<String>('mergeChunks', {
        'inputs': existing,
        'output': output.path,
      });

      if (merged == null) return null;
      final file = File(merged);
      if (!await file.exists() || await file.length() == 0) return null;

      debugPrint(
        'AudioMerge: ${existing.length} chunks -> '
        '${await file.length()} bytes',
      );
      return file;
    } on PlatformException catch (e) {
      // Sharing the chunks separately still works for shorter lectures.
      debugPrint('AudioMerge: failed (${e.code}) ${e.message}');
      return null;
    } on MissingPluginException {
      debugPrint('AudioMerge: not available on this platform');
      return null;
    }
  }

  /// Delete every cached merge for a recording.
  static Future<void> clearCache(String recordingId) async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains(recordingId)) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('AudioMerge: could not clear cache: $e');
    }
  }

  /// How much space every cached merge is using, in bytes.
  static Future<int> cacheSize() async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return 0;

      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (e) {
      debugPrint('AudioMerge: could not measure cache: $e');
      return 0;
    }
  }

  /// Delete every cached merge, returning how many bytes were freed.
  ///
  /// Safe at any time: these are copies of audio the app still holds, rebuilt
  /// on the next share. No recording is affected.
  static Future<int> clearAllCaches() async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return 0;

      final freed = await cacheSize();
      await dir.delete(recursive: true);
      return freed;
    } catch (e) {
      debugPrint('AudioMerge: could not clear cache: $e');
      return 0;
    }
  }

  static Future<Directory> _cacheDir() async {
    final temp = await getTemporaryDirectory();
    return Directory('${temp.path}/$_cacheDirName');
  }

  /// Output path keyed to the exact chunks merged.
  ///
  /// A lecture that gained a chunk since the last merge gets a different name,
  /// so a stale file is never shared.
  static Future<File> _outputFile(
    String recordingId,
    List<String> chunkPaths,
  ) async {
    final dir = await _cacheDir();
    if (!await dir.exists()) await dir.create(recursive: true);

    final signature = Object.hashAll(
      chunkPaths,
    ).toUnsigned(32).toRadixString(16);

    return File('${dir.path}/${recordingId}_$signature.m4a');
  }
}
