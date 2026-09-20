import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Service for capturing photos during a recording session.
///
/// Allows students to snap photos of the board, formulas, or slides
/// during recording. Photos are associated with a timestamp in
/// the recording so the AI can cross-reference them with the audio.
class PhotoCaptureService {
  final Uuid _uuid = const Uuid();
  final List<CapturedPhoto> _photos = [];

  /// All photos captured in the current session.
  List<CapturedPhoto> get photos => List.unmodifiable(_photos);

  /// Reset for a new recording session.
  void reset() {
    _photos.clear();
  }

  /// Register a photo that was captured during recording.
  ///
  /// [sourceFilePath] — the temporary path from the camera.
  /// [recordingId] — the current recording session ID.
  /// [timestampInRecording] — when in the recording this photo was taken.
  Future<CapturedPhoto> registerPhoto({
    required String sourceFilePath,
    required String recordingId,
    required Duration timestampInRecording,
    required int currentChunkIndex,
  }) async {
    final photoId = _uuid.v4();

    // Copy to recording's photos directory
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(
      '${docsDir.path}/recordings/$recordingId/photos',
    );
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final extension = sourceFilePath.split('.').last;
    final destPath = '${photosDir.path}/photo_$photoId.$extension';

    // Copy and compress
    final sourceFile = File(sourceFilePath);
    await sourceFile.copy(destPath);

    final destFile = File(destPath);
    final sizeBytes = await destFile.length();

    final photo = CapturedPhoto(
      id: photoId,
      recordingId: recordingId,
      filePath: destPath,
      timestampMs: timestampInRecording.inMilliseconds,
      chunkIndex: currentChunkIndex,
      sizeBytes: sizeBytes,
      capturedAt: DateTime.now(),
    );

    _photos.add(photo);
    debugPrint(
      'PhotoCaptureService: Photo captured at '
      '${timestampInRecording.inMinutes}m${timestampInRecording.inSeconds % 60}s '
      '(${(sizeBytes / 1024).toStringAsFixed(0)} KB)',
    );

    return photo;
  }

  /// Get all photos for a specific recording.
  List<CapturedPhoto> getPhotosForRecording(String recordingId) {
    return _photos.where((p) => p.recordingId == recordingId).toList();
  }

  /// Get photos for a specific chunk.
  List<CapturedPhoto> getPhotosForChunk(String recordingId, int chunkIndex) {
    return _photos
        .where(
          (p) => p.recordingId == recordingId && p.chunkIndex == chunkIndex,
        )
        .toList();
  }

  /// Delete all photos for a recording from disk.
  Future<void> deletePhotosForRecording(String recordingId) async {
    final toDelete = _photos.where((p) => p.recordingId == recordingId).toList();
    for (final photo in toDelete) {
      try {
        final file = File(photo.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('PhotoCaptureService: Failed to delete ${photo.filePath}');
      }
    }
    _photos.removeWhere((p) => p.recordingId == recordingId);
  }
}

/// A photo captured during a recording session.
class CapturedPhoto {
  final String id;
  final String recordingId;
  final String filePath;
  final int timestampMs;
  final int chunkIndex;
  final int sizeBytes;
  final DateTime capturedAt;

  const CapturedPhoto({
    required this.id,
    required this.recordingId,
    required this.filePath,
    required this.timestampMs,
    required this.chunkIndex,
    required this.sizeBytes,
    required this.capturedAt,
  });

  Duration get timestampDuration => Duration(milliseconds: timestampMs);

  String get timestampFormatted {
    final d = timestampDuration;
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}
