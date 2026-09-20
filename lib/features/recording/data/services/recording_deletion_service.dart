import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/services/audio_merge_service.dart';
import '../local/recording_dao.dart';

/// Deletes a recording everywhere it exists on this device.
///
/// Deleting used to remove database rows only, leaving the audio behind
/// forever. Here the audio is the only copy there is, so it has to go too.
class RecordingDeletionService {
  final RecordingDao _dao;
  final Future<Directory> Function(String recordingId) _recordingDir;

  RecordingDeletionService({
    required RecordingDao dao,
    Future<Directory> Function(String)? recordingDir,
  }) : this._(dao, recordingDir ?? _defaultRecordingDir);

  RecordingDeletionService._(this._dao, this._recordingDir);

  static Future<Directory> _defaultRecordingDir(String recordingId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    return Directory('${docsDir.path}/recordings/$recordingId');
  }

  /// Remove [recordingId]'s rows, audio, photos and any merged copy.
  Future<void> delete(String recordingId) async {
    await _deleteFiles(recordingId);
    await _dao.deleteRecording(recordingId);
  }

  /// Delete the audio directory and any captured photos.
  ///
  /// Failures here are logged, not thrown: leaving a stray file behind is a
  /// better outcome than a recording the user cannot remove.
  Future<void> _deleteFiles(String recordingId) async {
    try {
      for (final photo in await _dao.getPhotos(recordingId)) {
        final path = photo['file_path'] as String?;
        if (path == null) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('RecordingDeletion: could not delete photos: $e');
    }

    try {
      final dir = await _recordingDir(recordingId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('RecordingDeletion: could not delete audio: $e');
    }

    // The merged copy made for sharing lives in the cache directory, so it
    // would otherwise outlive the recording it came from.
    await AudioMergeService.clearCache(recordingId);
  }
}
