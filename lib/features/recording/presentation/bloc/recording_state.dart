import 'package:equatable/equatable.dart';

import '../../data/services/photo_capture_service.dart';

/// States for the Recording BLoC.
sealed class RecordingBlocState extends Equatable {
  const RecordingBlocState();

  @override
  List<Object?> get props => [];
}

/// Ready to start a recording.
class RecordingIdle extends RecordingBlocState {
  const RecordingIdle();
}

/// Requesting permissions before recording.
class RecordingRequestingPermissions extends RecordingBlocState {
  const RecordingRequestingPermissions();
}

/// Actively recording audio.
class RecordingInProgress extends RecordingBlocState {
  final String recordingId;
  final Duration totalDuration;
  final Duration chunkDuration;
  final int chunkIndex;
  final int completedChunks;
  final double amplitude;
  final List<CapturedPhoto> photos;
  final int availableStorageMB;
  final bool isStorageLow;
  final bool isNearMaxDuration;

  const RecordingInProgress({
    required this.recordingId,
    this.totalDuration = Duration.zero,
    this.chunkDuration = Duration.zero,
    this.chunkIndex = 0,
    this.completedChunks = 0,
    this.amplitude = 0.0,
    this.photos = const [],
    this.availableStorageMB = -1,
    this.isStorageLow = false,
    this.isNearMaxDuration = false,
  });

  RecordingInProgress copyWith({
    Duration? totalDuration,
    Duration? chunkDuration,
    int? chunkIndex,
    int? completedChunks,
    double? amplitude,
    List<CapturedPhoto>? photos,
    int? availableStorageMB,
    bool? isStorageLow,
    bool? isNearMaxDuration,
  }) {
    return RecordingInProgress(
      recordingId: recordingId,
      totalDuration: totalDuration ?? this.totalDuration,
      chunkDuration: chunkDuration ?? this.chunkDuration,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      completedChunks: completedChunks ?? this.completedChunks,
      amplitude: amplitude ?? this.amplitude,
      photos: photos ?? this.photos,
      availableStorageMB: availableStorageMB ?? this.availableStorageMB,
      isStorageLow: isStorageLow ?? this.isStorageLow,
      isNearMaxDuration: isNearMaxDuration ?? this.isNearMaxDuration,
    );
  }

  String get formattedDuration {
    final hours = totalDuration.inHours.toString().padLeft(2, '0');
    final minutes =
        (totalDuration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds =
        (totalDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  List<Object?> get props => [
        recordingId,
        totalDuration,
        chunkDuration,
        chunkIndex,
        completedChunks,
        amplitude,
        photos,
        availableStorageMB,
        isStorageLow,
        isNearMaxDuration,
      ];
}

/// Recording is paused.
class RecordingPaused extends RecordingBlocState {
  final String recordingId;
  final Duration totalDuration;
  final int completedChunks;
  final List<CapturedPhoto> photos;
  final int availableStorageMB;

  const RecordingPaused({
    required this.recordingId,
    required this.totalDuration,
    this.completedChunks = 0,
    this.photos = const [],
    this.availableStorageMB = -1,
  });

  String get formattedDuration {
    final hours = totalDuration.inHours.toString().padLeft(2, '0');
    final minutes =
        (totalDuration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds =
        (totalDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  List<Object?> get props => [
        recordingId,
        totalDuration,
        completedChunks,
        photos,
        availableStorageMB,
      ];
}

/// Recording has been stopped and saved.
class RecordingCompleted extends RecordingBlocState {
  final String recordingId;
  final Duration totalDuration;
  final int totalChunks;
  final int totalPhotos;
  final String recordingPath;
  final bool stoppedAtMaxDuration;

  const RecordingCompleted({
    required this.recordingId,
    required this.totalDuration,
    required this.totalChunks,
    required this.totalPhotos,
    required this.recordingPath,
    this.stoppedAtMaxDuration = false,
  });

  @override
  List<Object?> get props => [
        recordingId,
        totalDuration,
        totalChunks,
        totalPhotos,
        recordingPath,
        stoppedAtMaxDuration,
      ];
}

/// An error occurred during recording.
class RecordingError extends RecordingBlocState {
  final String message;
  final bool canRetry;

  const RecordingError({
    required this.message,
    this.canRetry = true,
  });

  @override
  List<Object?> get props => [message, canRetry];
}
