// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../data/local/recording_dao.dart';
import '../../data/services/audio_recorder_service.dart';
import '../../data/services/photo_capture_service.dart';
import '../../data/services/storage_monitor_service.dart';
import 'recording_event.dart';
import 'recording_state.dart';

/// Recording BLoC — orchestrates the full recording experience.
///
/// Coordinates between:
/// - [AudioRecorderService] for actual audio capture
/// - [StorageMonitorService] for storage tracking
/// - [PhotoCaptureService] for board/formula photos
/// - [PermissionService] for runtime permissions
/// - [RecordingDao] for local persistence (crash recovery)
///
/// A recording uses one on-device UUID everywhere (local files, local DB,
/// backend), so a recording started offline syncs under the same ID later.
class RecordingBloc extends Bloc<RecordingBlocEvent, RecordingBlocState> {
  final AudioRecorderService _recorderService;
  final StorageMonitorService _storageMonitor;
  final PhotoCaptureService _photoService;
  final PermissionService _permissionService;
  final RecordingDao _recordingDao;
  final Uuid _uuid = const Uuid();

  StreamSubscription<RecordingEvent>? _recorderSub;
  StreamSubscription<StorageStatus>? _storageSub;

  // Track state for rebuilding after internal events
  String? _recordingId;
  int _completedChunks = 0;
  int _reportedChunkDurationMs = 0;
  String _currentTitle = '';
  bool _isNearMaxDuration = false;
  bool _stoppedAtMaxDuration = false;

  RecordingBloc({
    required AudioRecorderService recorderService,
    required StorageMonitorService storageMonitor,
    required PhotoCaptureService photoService,
    required PermissionService permissionService,
    required RecordingDao recordingDao,
  })  : _recorderService = recorderService,
        _storageMonitor = storageMonitor,
        _photoService = photoService,
        _permissionService = permissionService,
        _recordingDao = recordingDao,
        super(const RecordingIdle()) {
    on<StartRecordingEvent>(_onStartRecording);
    on<PauseRecordingEvent>(_onPauseRecording);
    on<ResumeRecordingEvent>(_onResumeRecording);
    on<StopRecordingEvent>(_onStopRecording);
    on<CapturePhotoEvent>(_onCapturePhoto);
    on<AmplitudeUpdatedEvent>(_onAmplitudeUpdated);
    on<DurationTickEvent>(_onDurationTick);
    on<ChunkCompletedBlocEvent>(_onChunkCompleted);
    on<StorageStatusChangedEvent>(_onStorageStatusChanged);
    on<MaxDurationWarningBlocEvent>(_onMaxDurationWarning);
    on<RecordingErrorOccurredEvent>(_onError);
  }

  Future<void> _onStartRecording(
    StartRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    // Request permissions first
    emit(const RecordingRequestingPermissions());

    final hasMic = await _permissionService.requestMicrophone();
    if (!hasMic) {
      emit(const RecordingError(
        message: 'Microphone permission is required to record lectures.',
        canRetry: true,
      ));
      return;
    }

    // Generate recording ID and title
    final recordingId = _uuid.v4();
    _currentTitle = event.title ??
        'Recording ${DateTime.now().day}/${DateTime.now().month} '
            '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';

    // Reset state
    _recordingId = recordingId;
    _completedChunks = 0;
    _reportedChunkDurationMs = 0;
    _isNearMaxDuration = false;
    _stoppedAtMaxDuration = false;
    _photoService.reset();

    // Persist recording to local DB (crash recovery)
    try {
      await _recordingDao.insertRecording(
        id: recordingId,
        subjectId: event.subjectId,
        title: _currentTitle,
      );
    } catch (e) {
      debugPrint('RecordingBloc: Failed to persist recording locally: $e');
    }

    // Listen to recorder events
    _recorderSub?.cancel();
    _recorderSub = _recorderService.events.listen(_handleRecorderEvent);

    // Listen to storage events
    _storageSub?.cancel();
    _storageMonitor.startMonitoring();
    _storageSub = _storageMonitor.statusStream.listen((status) {
      add(StorageStatusChangedEvent(
        availableMB: status.availableMB,
        isLow: status.isLow,
      ));
    });

    try {
      await _recorderService.startRecording(recordingId);
    } catch (e) {
      emit(RecordingError(
        message: ErrorMessages.from(e, action: 'start recording'),
        canRetry: true,
      ));
      return;
    }

    // startRecording reports permission/storage failures via an error event
    if (!_recorderService.isRecording) return;

    emit(RecordingInProgress(recordingId: recordingId));
  }

  Future<void> _onPauseRecording(
    PauseRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;

    await _recorderService.pauseRecording();

    emit(RecordingPaused(
      recordingId: current.recordingId,
      totalDuration: current.totalDuration,
      completedChunks: _completedChunks,
      photos: current.photos,
      availableStorageMB: current.availableStorageMB,
    ));
  }

  Future<void> _onResumeRecording(
    ResumeRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (state is! RecordingPaused) return;
    final current = state as RecordingPaused;

    await _recorderService.resumeRecording();

    emit(RecordingInProgress(
      recordingId: current.recordingId,
      totalDuration: current.totalDuration,
      completedChunks: current.completedChunks,
      photos: current.photos,
      availableStorageMB: current.availableStorageMB,
      isNearMaxDuration: _isNearMaxDuration,
    ));
  }

  Future<void> _onStopRecording(
    StopRecordingEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (_getCurrentRecordingId() == null) return;

    // Stop recording — this saves the final chunk file
    final result = await _recorderService.stopRecording();

    // IMPORTANT: Give a brief moment for the final ChunkCompletedEvent
    // to propagate through the stream before we cancel subscriptions
    await Future<void>.delayed(const Duration(milliseconds: 100));

    _storageMonitor.stopMonitoring();
    _recorderSub?.cancel();
    _storageSub?.cancel();

    if (result == null) {
      emit(const RecordingIdle());
      return;
    }

    final durationMs = result.totalDuration.inMilliseconds;

    // If the final chunk wasn't picked up by the stream listener,
    // enqueue it manually.
    if (_completedChunks < result.totalChunks) {
      // The final chunk file path follows the naming pattern from AudioRecorderService
      final lastChunkIndex = result.totalChunks - 1;
      final chunkFileName = 'chunk_${lastChunkIndex.toString().padLeft(3, '0')}.m4a';
      final chunkPath = '${result.recordingPath}/$chunkFileName';

      final file = File(chunkPath);
      if (await file.exists()) {
        debugPrint('RecordingBloc: Manually enqueuing final chunk $lastChunkIndex');
        _completedChunks++;
        await _saveChunk(
          recordingId: result.recordingId,
          chunkIndex: lastChunkIndex,
          filePath: chunkPath,
          durationMs: (durationMs - _reportedChunkDurationMs).clamp(0, durationMs),
          sizeBytes: await file.length(),
        );
      }
    }

    // Update local DB with final status
    try {
      await _recordingDao.updateRecording(
        id: result.recordingId,
        status: 'completed',
        totalDurationMs: durationMs,
      );
    } catch (e) {
      debugPrint('RecordingBloc: Failed to update recording in DB: $e');
    }

    emit(RecordingCompleted(
      recordingId: result.recordingId,
      totalDuration: result.totalDuration,
      totalChunks: result.totalChunks,
      totalPhotos: _photoService.photos.length,
      recordingPath: result.recordingPath,
      stoppedAtMaxDuration: _stoppedAtMaxDuration,
    ));
  }

  Future<void> _onCapturePhoto(
    CapturePhotoEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;

    try {
      final photo = await _photoService.registerPhoto(
        sourceFilePath: event.photoFilePath,
        recordingId: current.recordingId,
        timestampInRecording: current.totalDuration,
        currentChunkIndex: current.chunkIndex,
      );

      // Photos stay on-device (upload_status = pending) until the backend
      // has a photo endpoint; uploading them now only blocks the sync queue.
      try {
        await _recordingDao.insertPhoto(
          id: photo.id,
          recordingId: photo.recordingId,
          chunkIndex: photo.chunkIndex,
          filePath: photo.filePath,
          timestampMs: photo.timestampMs,
          sizeBytes: photo.sizeBytes,
        );
      } catch (e) {
        debugPrint('RecordingBloc: Failed to persist photo: $e');
      }

      emit(current.copyWith(
        photos: [...current.photos, photo],
      ));
    } catch (e) {
      // Don't interrupt recording for a photo error
      debugPrint('RecordingBloc: Photo capture error: $e');
    }
  }

  void _onAmplitudeUpdated(
    AmplitudeUpdatedEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;
    emit(current.copyWith(amplitude: event.amplitude));
  }

  void _onDurationTick(
    DurationTickEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;
    emit(current.copyWith(
      totalDuration: event.totalDuration,
      chunkDuration: event.chunkDuration,
      chunkIndex: event.chunkIndex,
    ));
  }

  Future<void> _onChunkCompleted(
    ChunkCompletedBlocEvent event,
    Emitter<RecordingBlocState> emit,
  ) async {
    // Handle chunks whatever the UI state — the final chunk arrives while
    // paused when the user stops from a paused recording.
    final recordingId = _recordingId;
    if (recordingId == null) return;

    _completedChunks++;
    await _saveChunk(
      recordingId: recordingId,
      chunkIndex: event.chunkIndex,
      filePath: event.filePath,
      durationMs: event.durationMs,
      sizeBytes: event.sizeBytes,
    );

    if (state is RecordingInProgress) {
      emit((state as RecordingInProgress).copyWith(
        completedChunks: _completedChunks,
      ));
    }
  }

  /// Persist a finished chunk locally and enqueue it for upload.
  Future<void> _saveChunk({
    required String recordingId,
    required int chunkIndex,
    required String filePath,
    required int durationMs,
    required int sizeBytes,
  }) async {
    _reportedChunkDurationMs += durationMs;

    try {
      await _recordingDao.insertChunk(
        id: _uuid.v4(),
        recordingId: recordingId,
        sequenceNumber: chunkIndex,
        filePath: filePath,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
      );
    } catch (e) {
      debugPrint('RecordingBloc: Failed to persist chunk: $e');
    }
  }

  void _onStorageStatusChanged(
    StorageStatusChangedEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    if (state is! RecordingInProgress) return;
    final current = state as RecordingInProgress;
    emit(current.copyWith(
      availableStorageMB: event.availableMB,
      isStorageLow: event.isLow,
    ));
  }

  void _onMaxDurationWarning(
    MaxDurationWarningBlocEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    _isNearMaxDuration = true;
    if (state is RecordingInProgress) {
      emit((state as RecordingInProgress).copyWith(isNearMaxDuration: true));
    }
  }

  void _onError(
    RecordingErrorOccurredEvent event,
    Emitter<RecordingBlocState> emit,
  ) {
    emit(RecordingError(message: event.message));
  }

  /// Route recorder events to BLoC events.
  void _handleRecorderEvent(RecordingEvent event) {
    switch (event) {
      case AmplitudeEvent(:final normalizedAmplitude):
        add(AmplitudeUpdatedEvent(normalizedAmplitude));
      case DurationUpdateEvent(
          :final totalDuration,
          :final chunkDuration,
          :final chunkIndex
        ):
        add(DurationTickEvent(
          totalDuration: totalDuration,
          chunkDuration: chunkDuration,
          chunkIndex: chunkIndex,
        ));
      case ChunkCompletedEvent(
          :final chunkIndex,
          :final filePath,
          :final duration,
          :final sizeBytes
        ):
        add(ChunkCompletedBlocEvent(
          chunkIndex: chunkIndex,
          filePath: filePath,
          durationMs: duration.inMilliseconds,
          sizeBytes: sizeBytes,
        ));
      case MaxDurationWarningEvent():
        add(const MaxDurationWarningBlocEvent());
      case MaxDurationReachedEvent():
        _stoppedAtMaxDuration = true;
        add(const StopRecordingEvent());
      case RecordingErrorEvent(:final message):
        add(RecordingErrorOccurredEvent(message));
      case RecordingStartedEvent():
      case RecordingStoppedEvent():
      case RecordingPausedEvent():
      case RecordingResumedEvent():
      case ChunkDurationAdjustedEvent():
        break;
    }
  }

  String? _getCurrentRecordingId() {
    if (state is RecordingInProgress) {
      return (state as RecordingInProgress).recordingId;
    }
    if (state is RecordingPaused) {
      return (state as RecordingPaused).recordingId;
    }
    return null;
  }

  @override
  Future<void> close() async {
    _recorderSub?.cancel();
    _storageSub?.cancel();
    _storageMonitor.stopMonitoring();
    return super.close();
  }
}
