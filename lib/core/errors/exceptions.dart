/// Custom exception classes for Lecto
///
/// These exceptions represent specific failure modes
/// throughout the app.
library;

/// Thrown when a server/API call fails
class ServerException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const ServerException({
    required this.message,
    this.statusCode,
    this.code,
  });

  @override
  String toString() =>
      'ServerException(message: $message, '
      'statusCode: $statusCode, code: $code)';
}

/// Thrown when local cache/database operations fail
class CacheException implements Exception {
  final String message;

  const CacheException({required this.message});

  @override
  String toString() => 'CacheException(message: $message)';
}

/// Thrown when there's no network connectivity
class NetworkException implements Exception {
  final String message;

  const NetworkException({
    this.message = 'No internet connection. '
        'Please check your network.',
  });

  @override
  String toString() => 'NetworkException(message: $message)';
}

/// Thrown when audio recording fails
class RecordingException implements Exception {
  final String message;
  final String? details;

  const RecordingException({
    required this.message,
    this.details,
  });

  @override
  String toString() =>
      'RecordingException(message: $message, '
      'details: $details)';
}

/// Thrown when storage is insufficient
class StorageException implements Exception {
  final String message;
  final int? availableMB;

  const StorageException({
    required this.message,
    this.availableMB,
  });

  @override
  String toString() =>
      'StorageException(message: $message, '
      'availableMB: $availableMB)';
}

/// Thrown when permission is denied
class PermissionDeniedException implements Exception {
  final String permission;
  final String message;

  const PermissionDeniedException({
    required this.permission,
    this.message = 'Permission denied',
  });

  @override
  String toString() =>
      'PermissionDeniedException(permission: $permission)';
}
