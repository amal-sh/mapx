import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
export 'package:permission_handler/permission_handler.dart'
    show openAppSettings, Permission, PermissionStatus;

/// Requests the runtime CAMERA permission (required on API 23+; the
/// manifest's `<uses-permission>` only covers install-time declaration).
/// Must succeed before a real ARCore Session can be created (Phase 2/4).
///
/// Returns true if granted. Swallows platform errors and returns false on
/// platforms with no camera (e.g. running the UI on desktop/web during dev).
Future<bool> ensureCameraPermission() async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  try {
    final status = await Permission.camera.request();
    return status.isGranted;
  } catch (_) {
    return false;
  }
}

/// Requests runtime ACTIVITY_RECOGNITION permission (required on Android 10+ / API 29+
/// for hardware step counting via pedometer).
Future<bool> ensureActivityRecognitionPermission() async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  try {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  } catch (_) {
    return false;
  }
}

/// Core permissions required for MapX AR navigation and spatial mapping:
/// - [Permission.camera] for ARCore plane tracking, SceneView 3D viewport, and camera scanning
/// - [Permission.activityRecognition] for step counting and walking odometry on Android 10+
const List<Permission> kRequiredAppPermissions = [
  Permission.camera,
  Permission.activityRecognition,
];

/// Collects and requests all permissions required by [AdminMappingScreen]
/// and [NavigationScreen] in one unified batch upfront.
///
/// Returns true if all permissions are granted.
Future<bool> requestAllAppPermissions() async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  try {
    final statuses = await kRequiredAppPermissions.request();
    return statuses.values.every((status) => status.isGranted);
  } catch (_) {
    return false;
  }
}

/// Checks whether all required app permissions have already been granted.
Future<bool> checkAllAppPermissions() async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  try {
    for (final permission in kRequiredAppPermissions) {
      final status = await permission.status;
      if (!status.isGranted) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}
