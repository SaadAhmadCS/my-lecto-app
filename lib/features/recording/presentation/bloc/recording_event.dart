import 'package:equatable/equatable.dart';

/// Events for the Recording BLoC.
sealed class RecordingBlocEvent extends Equatable {
  const RecordingBlocEvent();

  @override
  List<Object?> get props => [];
}

/// Start a new recording in the given subject.
class StartRecordingEvent extends RecordingBlocEvent {
  final String subjectId;
  final String? title;

  const StartRecordingEvent({required this.subjectId, this.title});

  @override
  List<Object?> get props => [subjectId, title];
}

/// Pause the current recording.
class PauseRecordingEvent extends RecordingBlocEvent {
  const PauseRecordingEvent();
}

/// Resume a paused recording.
class ResumeRecordingEvent extends RecordingBlocEvent {
  const ResumeRecordingEvent();
}

/// Stop and save the current recording.
class StopRecordingEvent extends RecordingBlocEvent {
  const StopRecordingEvent();
}

/// Clear a finished or failed session so the next one starts fresh.
///
/// The bloc lives for the whole app so a recording survives leaving its
/// screen; this is what returns it to idle afterwards. Ignored mid-recording.
class ResetRecordingEvent extends RecordingBlocEvent {
  const ResetRecordingEvent();
}

/// Capture a photo of the board during recording.
class CapturePhotoEvent extends RecordingBlocEvent {
  final String photoFilePath;

  const CapturePhotoEvent({required this.photoFilePath});

  @override
  List<Object?> get props => [photoFilePath];
}

/// Internal: amplitude update from recorder.
class AmplitudeUpdatedEvent extends RecordingBlocEvent {
  final double amplitude;

  const AmplitudeUpdatedEvent(this.amplitude);

  @override
  List<Object?> get props => [amplitude];
}

/// Internal: duration tick from recorder.
class DurationTickEvent extends RecordingBlocEvent {
  final Duration totalDuration;
  final Duration chunkDuration;
  final int chunkIndex;

  const DurationTickEvent({
    required this.totalDuration,
    required this.chunkDuration,
    required this.chunkIndex,
  });

  @override
  List<Object?> get props => [totalDuration, chunkDuration, chunkIndex];
}

/// Internal: a chunk was completed and saved.
class ChunkCompletedBlocEvent extends RecordingBlocEvent {
  final int chunkIndex;
  final String filePath;
  final int durationMs;
  final int sizeBytes;

  const ChunkCompletedBlocEvent({
    required this.chunkIndex,
    required this.filePath,
    required this.durationMs,
    required this.sizeBytes,
  });

  @override
  List<Object?> get props => [chunkIndex, filePath, durationMs, sizeBytes];
}

/// Internal: storage status changed.
class StorageStatusChangedEvent extends RecordingBlocEvent {
  final int availableMB;
  final bool isLow;

  const StorageStatusChangedEvent({
    required this.availableMB,
    required this.isLow,
  });

  @override
  List<Object?> get props => [availableMB, isLow];
}

/// Internal: the session is 15 minutes from the 8-hour limit.
class MaxDurationWarningBlocEvent extends RecordingBlocEvent {
  const MaxDurationWarningBlocEvent();
}

/// Internal: an error occurred.
class RecordingErrorOccurredEvent extends RecordingBlocEvent {
  final String message;

  const RecordingErrorOccurredEvent(this.message);

  @override
  List<Object?> get props => [message];
}
