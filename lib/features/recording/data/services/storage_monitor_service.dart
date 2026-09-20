import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Storage monitoring service for Lecto.
///
/// Tracks available device storage and provides:
/// - Real-time storage status events
/// - Dynamic chunk duration calculation when storage is low
/// - Estimated remaining recording time based on bitrate
class StorageMonitorService {
  /// Thresholds in megabytes
  static const int warningThresholdMB = 500;
  static const int criticalThresholdMB = 100;
  static const int fullThresholdMB = 20;

  /// Average audio file size: ~1MB per minute at 128kbps AAC
  static const double mbPerMinute = 1.0;

  Timer? _pollingTimer;
  final _statusController = StreamController<StorageStatus>.broadcast();

  /// Stream of storage status updates.
  Stream<StorageStatus> get statusStream => _statusController.stream;

  /// Start periodic storage monitoring.
  void startMonitoring({
    Duration interval = const Duration(seconds: 30),
  }) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) async {
      final status = await checkStorage();
      _statusController.add(status);
    });

    // Emit initial status immediately
    checkStorage().then(_statusController.add);
  }

  /// Stop monitoring.
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Check current storage status.
  Future<StorageStatus> checkStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stat = await _getStorageInfo(dir.path);
      final freeMB = stat ~/ (1024 * 1024);

      StorageLevel level;
      if (freeMB <= fullThresholdMB) {
        level = StorageLevel.full;
      } else if (freeMB <= criticalThresholdMB) {
        level = StorageLevel.critical;
      } else if (freeMB <= warningThresholdMB) {
        level = StorageLevel.warning;
      } else {
        level = StorageLevel.normal;
      }

      return StorageStatus(
        availableMB: freeMB,
        level: level,
        estimatedMinutesRemaining:
            (freeMB * 0.8 / mbPerMinute).floor(), // 80% safety margin
      );
    } catch (e) {
      return const StorageStatus(
        availableMB: -1,
        level: StorageLevel.unknown,
        estimatedMinutesRemaining: -1,
      );
    }
  }

  /// Calculate a safe chunk duration based on remaining storage.
  ///
  /// When storage is low, we shorten chunks so we don't run out
  /// mid-chunk. Always reserves 20MB as emergency buffer.
  int calculateSafeChunkDuration({
    required int availableMB,
    int defaultChunkMinutes = 15,
    int minChunkMinutes = 3,
  }) {
    final usableMB = (availableMB - fullThresholdMB).clamp(0, availableMB);
    final maxMinutes = (usableMB * 0.7 / mbPerMinute).floor();

    if (maxMinutes <= 0) return 0; // No space at all
    if (maxMinutes < minChunkMinutes) return minChunkMinutes;
    if (maxMinutes < defaultChunkMinutes) return maxMinutes;
    return defaultChunkMinutes;
  }

  /// Get the path where recordings are stored.
  Future<String> getRecordingsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return recordingsDir.path;
  }

  /// Get total size of all local recordings in MB.
  Future<int> getLocalRecordingsSizeMB() async {
    try {
      final dirPath = await getRecordingsDirectory();
      final dir = Directory(dirPath);
      if (!await dir.exists()) return 0;

      int totalBytes = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
      return totalBytes ~/ (1024 * 1024);
    } catch (e) {
      return 0;
    }
  }

  /// Get available free space for the given path.
  Future<int> _getStorageInfo(String path) async {
    try {
      final stat = await FileStat.stat(path);
      // On Android, we can use the disk space from the file system
      // For a more accurate reading, we check the partition
      if (Platform.isAndroid) {
        final statFs = await Process.run(
          'df',
          ['-k', path],
        );
        if (statFs.exitCode == 0) {
          final lines = (statFs.stdout as String).split('\n');
          if (lines.length >= 2) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              // Available space in KB → convert to bytes
              final availableKB = int.tryParse(parts[3]);
              if (availableKB != null) {
                return availableKB * 1024;
              }
            }
          }
        }
      }
      // Fallback: return a large number (assume plenty of space)
      return stat.size > 0 ? stat.size : 2 * 1024 * 1024 * 1024;
    } catch (e) {
      return 2 * 1024 * 1024 * 1024; // Default 2GB
    }
  }

  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}

/// Current storage status.
class StorageStatus {
  final int availableMB;
  final StorageLevel level;
  final int estimatedMinutesRemaining;

  const StorageStatus({
    required this.availableMB,
    required this.level,
    required this.estimatedMinutesRemaining,
  });

  bool get isLow =>
      level == StorageLevel.warning ||
      level == StorageLevel.critical ||
      level == StorageLevel.full;

  bool get canRecord =>
      level != StorageLevel.full && level != StorageLevel.unknown;

  String get displayText {
    if (availableMB < 0) return 'Unknown';
    if (availableMB >= 1024) {
      return '${(availableMB / 1024).toStringAsFixed(1)} GB free';
    }
    return '$availableMB MB free';
  }
}

/// Storage level classification.
enum StorageLevel {
  normal,   // > 500MB
  warning,  // 100-500MB
  critical, // 20-100MB
  full,     // < 20MB
  unknown,  // Could not determine
}
