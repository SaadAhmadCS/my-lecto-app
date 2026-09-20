import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized permission management for Lecto.
///
/// Handles requesting, checking, and explaining permissions
/// for microphone, camera, storage, and notifications.
class PermissionService {
  /// Check and request microphone permission.
  /// Returns true if granted.
  Future<bool> requestMicrophone() async {
    return _requestPermission(
      Permission.microphone,
      'Microphone',
      'Lecto needs microphone access to record lectures.',
    );
  }

  /// Check and request camera permission.
  /// Returns true if granted.
  Future<bool> requestCamera() async {
    return _requestPermission(
      Permission.camera,
      'Camera',
      'Lecto needs camera access to capture board photos.',
    );
  }

  /// Check and request notification permission (Android 13+).
  Future<bool> requestNotifications() async {
    return _requestPermission(
      Permission.notification,
      'Notifications',
      'Lecto needs notifications to show recording status.',
    );
  }

  /// Check if microphone permission is granted.
  Future<bool> hasMicrophone() async {
    return (await Permission.microphone.status).isGranted;
  }

  /// Check if camera permission is granted.
  Future<bool> hasCamera() async {
    return (await Permission.camera.status).isGranted;
  }

  /// Request all recording-related permissions at once.
  /// Returns a map of permission name → granted status.
  Future<Map<String, bool>> requestRecordingPermissions() async {
    final results = <String, bool>{};
    results['microphone'] = await requestMicrophone();
    results['camera'] = await requestCamera();
    results['notifications'] = await requestNotifications();
    return results;
  }

  /// Check if all recording permissions are granted.
  Future<bool> hasAllRecordingPermissions() async {
    final mic = await hasMicrophone();
    final cam = await hasCamera();
    return mic && cam;
  }

  /// Open app settings for the user to manually grant permissions.
  Future<bool> openSettings() async {
    return openAppSettings();
  }

  /// Internal helper to request a single permission with logging.
  Future<bool> _requestPermission(
    Permission permission,
    String name,
    String rationale,
  ) async {
    final status = await permission.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      // User must go to settings
      debugPrint(
        'PermissionService: $name permanently denied. '
        'User must enable in settings.',
      );
      return false;
    }

    // Request the permission
    final result = await permission.request();
    debugPrint('PermissionService: $name request result: $result');
    return result.isGranted;
  }
}
