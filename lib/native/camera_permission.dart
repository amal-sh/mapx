import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime CAMERA permission (required on API 23+; the
/// manifest's `<uses-permission>` only covers install-time declaration).
/// Must succeed before a real ARCore Session can be created (Phase 2/4).
///
/// Returns true if granted. Swallows platform errors and returns false on
/// platforms with no camera (e.g. running the UI on desktop/web during dev).
Future<bool> ensureCameraPermission() async {
  try {
    final status = await Permission.camera.request();
    return status.isGranted;
  } catch (_) {
    return false;
  }
}
