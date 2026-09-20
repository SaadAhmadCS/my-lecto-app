// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'storage_monitor_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/foreground_recording_service.dart';

/// Core audio recording service for Lecto.
///
/// Manages the full recording lifecycle:
/// - Start/stop/pause/resume recording
/// - Auto-chunking at configurable intervals
/// - Amplitude streaming for waveform visualization
/// - Dynamic chunk sizing based on storage availability
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  final StorageMonitorService _storageMonitor;

  Timer? _durationTimer;
  final _eventController = StreamController<RecordingEvent>.broadcast();

  // Current recording state
  String? _currentRecordingId;
  String? _currentChunkPath;
  int _currentChunkIndex = 0;
  int _chunkDurationMinutes = 15;
  Duration _totalDuration = Duration.zero;
  Duration _chunkDuration = Duration.zero;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isRotating = false;
  bool _maxDurationWarned = false;
  bool _maxDurationReached = false;
  String _recordingsBasePath = '';

  AudioRecorderService({required StorageMonitorService storageMonitor})
      : _storageMonitor = storageMonitor;

  /// Stream of recording events (amplitude, chunk saved, errors).
  Stream<RecordingEvent> get events => _eventController.stream;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Duration get totalDuration => _totalDuration;
  Duration get chunkDuration => _chunkDuration;
  int get currentChunkIndex => _currentChunkIndex;
  String? get currentRecordingId => _currentRecordingId;

  /// Start a new recording session.
  ///
  /// Creates a directory for this recording and begins capturing audio.
  /// [recordingId] — unique ID for this recording session.
  /// [chunkMinutes] — minutes per chunk, adjusted down if storage is low.
  Future<void> startRecording(
    String recordingId, {
    int chunkMinutes = AppConstants.defaultChunkDurationMinutes,
  }) async {
    if (_isRecording) {
      throw StateError('Already recording. Stop current recording first.');
    }

    // Check permissions
    if (!await _recorder.hasPermission()) {
      _eventController.add(const RecordingEvent.error(
        'Microphone permission denied',
      ));
      return;
    }

    // Check storage
    final storageStatus = await _storageMonitor.checkStorage();
    if (!storageStatus.canRecord) {
      _eventController.add(const RecordingEvent.error(
        'Not enough storage space to record',
      ));
      return;
    }

    // Adjust chunk duration based on storage
    _chunkDurationMinutes = _storageMonitor.calculateSafeChunkDuration(
      availableMB: storageStatus.availableMB,
      defaultChunkMinutes: chunkMinutes,
    );

    if (_chunkDurationMinutes <= 0) {
      _eventController.add(const RecordingEvent.error(
        'Not enough storage for even a short recording',
      ));
      return;
    }

    // Setup recording directory
    _currentRecordingId = recordingId;
    _currentChunkIndex = 0;
    _totalDuration = Duration.zero;
    _maxDurationWarned = false;
    _maxDurationReached = false;
    _chunkDuration = Duration.zero;

    final docsDir = await getApplicationDocumentsDirectory();
    _recordingsBasePath = '${docsDir.path}/recordings/$recordingId';
    final recordingDir = Directory(_recordingsBasePath);
    if (!await recordingDir.exists()) {
      await recordingDir.create(recursive: true);
    }

    // Start first chunk
    await _startChunk();

    _isRecording = true;
    _isPaused = false;

    await ForegroundRecordingService.startService();

    // Start duration tracking timer
    _durationTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        if (_isRecording && !_isPaused) {
          _totalDuration += const Duration(milliseconds: 200);
          _chunkDuration += const Duration(milliseconds: 200);
          _eventController.add(RecordingEvent.durationUpdate(
            totalDuration: _totalDuration,
            chunkDuration: _chunkDuration,
            chunkIndex: _currentChunkIndex,
          ));

          // Update foreground notification every second
          if (_totalDuration.inMilliseconds % 1000 < 200) {
            ForegroundRecordingService.updateDuration(_totalDuration);
          }

          // Rotate on recorded time, not wall-clock time, so paused time
          // doesn't stretch a chunk past the STT file-size limits.
          if (!_isRotating &&
              _chunkDuration >= Duration(minutes: _chunkDurationMinutes)) {
            _rotateChunk();
          }

          _checkMaxDuration();
        }
      },
    );

    // Start amplitude monitoring
    _startAmplitudeMonitoring();

    _eventController.add(RecordingEvent.started(
      recordingId: recordingId,
      chunkDurationMinutes: _chunkDurationMinutes,
    ));

    debugPrint(
      'AudioRecorderService: Started recording $recordingId '
      '(chunk every $_chunkDurationMinutes min)',
    );
  }

  /// Stop the current recording completely.
  Future<RecordingResult?> stopRecording() async {
    if (!_isRecording) return null;

    _isRecording = false;
    _isPaused = false;
    _durationTimer?.cancel();

    await ForegroundRecordingService.stopService();

    // Stop and save the current chunk
    await _stopCurrentChunk();

    final result = RecordingResult(
      recordingId: _currentRecordingId!,
      totalDuration: _totalDuration,
      totalChunks: _currentChunkIndex + 1,
      recordingPath: _recordingsBasePath,
    );

    _eventController.add(RecordingEvent.stopped(result: result));

    debugPrint(
      'AudioRecorderService: Stopped recording. '
      '${result.totalChunks} chunks, ${result.totalDuration.inMinutes} min',
    );

    _currentRecordingId = null;
    return result;
  }

  /// Pause the recording.
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    await _recorder.pause();
    _isPaused = true;
    _eventController.add(const RecordingEvent.paused());
    debugPrint('AudioRecorderService: Paused');
  }

  /// Resume a paused recording.
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    await _recorder.resume();
    _isPaused = false;
    _eventController.add(const RecordingEvent.resumed());
    debugPrint('AudioRecorderService: Resumed');
  }

  /// Start recording a new chunk.
  Future<void> _startChunk() async {
    final chunkFileName = 'chunk_${_currentChunkIndex.toString().padLeft(3, '0')}.m4a';
    _currentChunkPath = '$_recordingsBasePath/$chunkFileName';

    const config = RecordConfig(
      encoder: AudioEncoder.aacHe,
      sampleRate: AppConstants.audioSampleRate,
      bitRate: AppConstants.audioBitRate,
      numChannels: 1, // Mono is fine for voice
    );

    await _recorder.start(config, path: _currentChunkPath!);
    debugPrint('AudioRecorderService: Chunk $_currentChunkIndex started');
  }

  /// Stop the current chunk and return its path.
  Future<String?> _stopCurrentChunk() async {
    try {
      final path = await _recorder.stop();

      if (path != null && _currentChunkPath != null) {
        final file = File(_currentChunkPath!);
        if (await file.exists()) {
          final sizeBytes = await file.length();
          _eventController.add(RecordingEvent.chunkCompleted(
            chunkIndex: _currentChunkIndex,
            filePath: _currentChunkPath!,
            duration: _chunkDuration,
            sizeBytes: sizeBytes,
          ));
        }
      }
      return path;
    } catch (e) {
      debugPrint('AudioRecorderService: Error stopping chunk: $e');
      return null;
    }
  }

  /// Emit the 8-hour warning and limit events once each. The owner stops
  /// the recording on [MaxDurationReachedEvent] so its normal stop flow
  /// (final chunk upload, completion) runs.
  void _checkMaxDuration() {
    if (!_maxDurationWarned &&
        _totalDuration >= AppConstants.maxRecordingWarningAt) {
      _maxDurationWarned = true;
      _eventController.add(const RecordingEvent.maxDurationWarning());
    }
    if (!_maxDurationReached &&
        _totalDuration >= AppConstants.maxRecordingDuration) {
      _maxDurationReached = true;
      _eventController.add(const RecordingEvent.maxDurationReached());
    }
  }

  /// Rotate to a new chunk (save current, start new).
  Future<void> _rotateChunk() async {
    if (!_isRecording || _isPaused || _isRotating) return;
    _isRotating = true;
    try {
      await _rotateChunkInner();
    } finally {
      _isRotating = false;
    }
  }

  Future<void> _rotateChunkInner() async {
    debugPrint('AudioRecorderService: Rotating chunk $_currentChunkIndex');

    // Stop current chunk
    await _stopCurrentChunk();

    // Check storage before starting new chunk
    final storageStatus = await _storageMonitor.checkStorage();
    if (!storageStatus.canRecord) {
      _eventController.add(const RecordingEvent.error(
        'Storage full. Recording stopped to prevent data loss.',
      ));
      await stopRecording();
      return;
    }

    // Update chunk duration if storage is getting low
    final newChunkDuration = _storageMonitor.calculateSafeChunkDuration(
      availableMB: storageStatus.availableMB,
      defaultChunkMinutes: _chunkDurationMinutes,
    );
    if (newChunkDuration != _chunkDurationMinutes) {
      _chunkDurationMinutes = newChunkDuration;
      _eventController.add(RecordingEvent.chunkDurationAdjusted(
        newDurationMinutes: _chunkDurationMinutes,
        reason: 'Low storage — chunks shortened',
      ));
    }

    // Start next chunk
    _currentChunkIndex++;
    _chunkDuration = Duration.zero;
    await _startChunk();
  }

  /// Monitor audio amplitude for waveform display.
  void _startAmplitudeMonitoring() {
    _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      if (_isRecording && !_isPaused) {
        // Normalize amplitude from dB to 0.0-1.0
        // amp.current is in dBFS (typically -160 to 0)
        final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        _eventController.add(RecordingEvent.amplitude(normalized));
      }
    });
  }

  /// Cancel and clean up everything.
  Future<void> dispose() async {
    _durationTimer?.cancel();
    if (_isRecording) {
      await _recorder.stop();
    }
    _recorder.dispose();
    await _eventController.close();
  }
}

/// Events emitted by the audio recorder.
sealed class RecordingEvent {
  const RecordingEvent();

  const factory RecordingEvent.started({
    required String recordingId,
    required int chunkDurationMinutes,
  }) = RecordingStartedEvent;

  const factory RecordingEvent.stopped({
    required RecordingResult result,
  }) = RecordingStoppedEvent;

  const factory RecordingEvent.paused() = RecordingPausedEvent;

  const factory RecordingEvent.resumed() = RecordingResumedEvent;

  const factory RecordingEvent.amplitude(double normalizedAmplitude) =
      AmplitudeEvent;

  const factory RecordingEvent.durationUpdate({
    required Duration totalDuration,
    required Duration chunkDuration,
    required int chunkIndex,
  }) = DurationUpdateEvent;

  const factory RecordingEvent.chunkCompleted({
    required int chunkIndex,
    required String filePath,
    required Duration duration,
    required int sizeBytes,
  }) = ChunkCompletedEvent;

  const factory RecordingEvent.chunkDurationAdjusted({
    required int newDurationMinutes,
    required String reason,
  }) = ChunkDurationAdjustedEvent;

  const factory RecordingEvent.maxDurationWarning() = MaxDurationWarningEvent;

  const factory RecordingEvent.maxDurationReached() = MaxDurationReachedEvent;

  const factory RecordingEvent.error(String message) = RecordingErrorEvent;
}

class RecordingStartedEvent extends RecordingEvent {
  final String recordingId;
  final int chunkDurationMinutes;
  const RecordingStartedEvent({
    required this.recordingId,
    required this.chunkDurationMinutes,
  });
}

class RecordingStoppedEvent extends RecordingEvent {
  final RecordingResult result;
  const RecordingStoppedEvent({required this.result});
}

class RecordingPausedEvent extends RecordingEvent {
  const RecordingPausedEvent();
}

class RecordingResumedEvent extends RecordingEvent {
  const RecordingResumedEvent();
}

class AmplitudeEvent extends RecordingEvent {
  final double normalizedAmplitude;
  const AmplitudeEvent(this.normalizedAmplitude);
}

class DurationUpdateEvent extends RecordingEvent {
  final Duration totalDuration;
  final Duration chunkDuration;
  final int chunkIndex;
  const DurationUpdateEvent({
    required this.totalDuration,
    required this.chunkDuration,
    required this.chunkIndex,
  });
}

class ChunkCompletedEvent extends RecordingEvent {
  final int chunkIndex;
  final String filePath;
  final Duration duration;
  final int sizeBytes;
  const ChunkCompletedEvent({
    required this.chunkIndex,
    required this.filePath,
    required this.duration,
    required this.sizeBytes,
  });
}

class ChunkDurationAdjustedEvent extends RecordingEvent {
  final int newDurationMinutes;
  final String reason;
  const ChunkDurationAdjustedEvent({
    required this.newDurationMinutes,
    required this.reason,
  });
}

class MaxDurationWarningEvent extends RecordingEvent {
  const MaxDurationWarningEvent();
}

class MaxDurationReachedEvent extends RecordingEvent {
  const MaxDurationReachedEvent();
}

class RecordingErrorEvent extends RecordingEvent {
  final String message;
  const RecordingErrorEvent(this.message);
}

/// Result returned when a recording session ends.
class RecordingResult {
  final String recordingId;
  final Duration totalDuration;
  final int totalChunks;
  final String recordingPath;

  const RecordingResult({
    required this.recordingId,
    required this.totalDuration,
    required this.totalChunks,
    required this.recordingPath,
  });
}
