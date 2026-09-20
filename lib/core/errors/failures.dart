import 'package:equatable/equatable.dart';

/// Base failure class for use case error handling.
///
/// Failures are returned from repositories/use cases,
/// while Exceptions are thrown at the data layer.
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({required this.message, this.code});

  @override
  List<Object?> get props => [message, code];
}

class ServerFailure extends Failure {
  final int? statusCode;

  const ServerFailure({
    required super.message,
    super.code,
    this.statusCode,
  });
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});
}

class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'No internet connection',
    super.code,
  });
}

class RecordingFailure extends Failure {
  const RecordingFailure({
    required super.message,
    super.code,
  });
}

class StorageFailure extends Failure {
  final int? availableMB;

  const StorageFailure({
    required super.message,
    super.code,
    this.availableMB,
  });
}

class PermissionFailure extends Failure {
  final String permission;

  const PermissionFailure({
    required super.message,
    required this.permission,
    super.code,
  });
}
