import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Real-time 3D physical device orientation tracker.
///
/// Uses hardware accelerometer (gravity vector) and magnetometer (geomagnetic field)
/// to compute tilt-compensated azimuth (yaw/heading), pitch, and roll in radians.
///
/// Anchors virtual AR objects to the physical world:
/// - When the user turns their body or camera left/right, [headingRadians] rotates.
/// - When the user tilts their phone up/down, [pitchRadians] updates.
/// - Includes a circular exponential moving average (EMA) filter to eliminate jitter.
/// - Supports [referenceHeadingOffset] for calibrating the floor/corridor forward axis.
class PhysicalOrientationTracker {
  PhysicalOrientationTracker({
    this.filterSmoothing = 0.35,
    double initialHeadingRadians = 0.0,
    double initialPitchRadians = -0.45, // ~26° downward tilt (natural phone reading posture)
    double initialRollRadians = 0.0,
  })  : _headingRadians = initialHeadingRadians,
        _pitchRadians = initialPitchRadians,
        _rollRadians = initialRollRadians;

  /// Low-pass filter smoothing coefficient (0.05 = heavy smoothing, 0.5 = raw/instant).
  final double filterSmoothing;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  double _ax = 0.0;
  double _ay = 9.8;
  double _az = 0.0;

  double _mx = 0.0;
  double _my = 0.0;
  double _mz = -35.0;

  bool _hasAccel = false;
  bool _hasMag = false;

  double _headingRadians;
  double _pitchRadians;
  double _rollRadians;

  /// User-calibrated offset (subtracted from raw azimuth to align with building axis).
  double _referenceHeadingOffset = 0.0;

  // Listeners for UI state updates
  final List<VoidCallback> _listeners = [];

  // Getters
  double get headingRadians => _normalizeAngle(_headingRadians - _referenceHeadingOffset);
  double get rawHeadingRadians => _headingRadians;
  double get headingDegrees => (headingRadians * 180 / math.pi) % 360;
  double get pitchRadians => _pitchRadians;
  double get pitchDegrees => _pitchRadians * 180 / math.pi;
  double get rollRadians => _rollRadians;
  double get rollDegrees => _rollRadians * 180 / math.pi;
  double get referenceHeadingOffset => _referenceHeadingOffset;

  /// Cardinal direction string (e.g. 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW').
  String get cardinalDirection {
    final deg = headingDegrees;
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((deg + 22.5) % 360 / 45).floor();
    return directions[idx.clamp(0, 7)];
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final l in List<VoidCallback>.from(_listeners)) {
      l();
    }
  }

  /// Starts listening to device hardware sensors.
  void start() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onAccelerometer, onError: (_) {});
    } catch (_) {}

    try {
      _magSub = magnetometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onMagnetometer, onError: (_) {});
    } catch (_) {}
  }

  /// Stops sensor streams.
  void stop() {
    _accelSub?.cancel();
    _magSub?.cancel();
    _accelSub = null;
    _magSub = null;
  }

  /// Disposes resources and listeners.
  void dispose() {
    stop();
    _listeners.clear();
  }

  /// Calibrates the current facing direction as 0 rad (Forward down the corridor).
  void calibrateCurrentAsForward() {
    _referenceHeadingOffset = _headingRadians;
    _notifyListeners();
  }

  /// Resets reference heading offset back to true geomagnetic North.
  void resetCalibration() {
    _referenceHeadingOffset = 0.0;
    _notifyListeners();
  }

  /// Manually rotates heading by [deltaRadians] (used by UI steppers & touch drag).
  void rotateHeading(double deltaRadians) {
    _referenceHeadingOffset -= deltaRadians;
    _referenceHeadingOffset = _normalizeAngle(_referenceHeadingOffset);
    _notifyListeners();
  }

  /// Manually sets the heading (useful for simulations and tests).
  void setHeading(double radians) {
    _referenceHeadingOffset = _normalizeAngle(_headingRadians - radians);
    _notifyListeners();
  }

  /// Manually sets the pitch (tilt up/down).
  void setPitch(double radians) {
    _pitchRadians = radians.clamp(-math.pi / 2, math.pi / 2);
    _notifyListeners();
  }

  /// Manually sets the roll (device wrist roll).
  void setRoll(double radians) {
    _rollRadians = radians.clamp(-math.pi, math.pi);
    _notifyListeners();
  }

  /// Hook for testing orientation calculations with direct sensor values.
  @visibleForTesting
  void updateSensorsForTesting({
    double? ax,
    double? ay,
    double? az,
    double? mx,
    double? my,
    double? mz,
  }) {
    if (ax != null) _ax = ax;
    if (ay != null) _ay = ay;
    if (az != null) _az = az;
    if (ax != null || ay != null || az != null) _hasAccel = true;
    if (mx != null) _mx = mx;
    if (my != null) _my = my;
    if (mz != null) _mz = mz;
    if (mx != null || my != null || mz != null) _hasMag = true;
    _computeOrientation();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    _ax = event.x;
    _ay = event.y;
    _az = event.z;
    _hasAccel = true;
    _computeOrientation();
  }

  void _onMagnetometer(MagnetometerEvent event) {
    _mx = event.x;
    _my = event.y;
    _mz = event.z;
    _hasMag = true;
    _computeOrientation();
  }

  /// Computes tilt-compensated orientation matrix matching Android's
  /// SensorManager.getRotationMatrix formulation for Portrait camera view.
  void _computeOrientation() {
    if (!_hasAccel) return;

    // Upward contact force unit vector: A = ||A|| (measured by accelerometer)
    final normA = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
    if (normA < 0.1) return;
    final ax = _ax / normA;
    final ay = _ay / normA;
    final az = _az / normA;

    // Pitch: angle between camera line-of-sight (-Z) and the horizontal plane.
    // Upright portrait: ay ~= 1, az ~= 0 -> pitch = 0 (horizontal forward)
    // Tilting down at floor: az > 0, ay > 0 -> pitch < 0 (looking down)
    // Tilting up at ceiling: az < 0, ay > 0 -> pitch > 0 (looking up)
    final targetPitch = math.atan2(-az, math.sqrt(ax * ax + ay * ay));
    _pitchRadians += filterSmoothing * (targetPitch - _pitchRadians);

    // Roll: rotation around device screen normal (camera optical axis)
    // Rolling right: ax > 0 -> roll > 0
    // Rolling left: ax < 0 -> roll < 0
    final targetRoll = math.atan2(ax, ay);
    _rollRadians += filterSmoothing * (targetRoll - _rollRadians);

    // Azimuth (Heading) calculation:
    if (_hasMag) {
      // H = M x A (East vector, horizontal)
      // M is geomagnetic field (North/down), A is upward contact force
      // North x Up = East
      var hx = _my * az - _mz * ay;
      var hy = _mz * ax - _mx * az;
      var hz = _mx * ay - _my * ax;
      final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
      if (normH > 0.1) {
        hx /= normH;
        hy /= normH;
        hz /= normH;

        // M' = A x H (North vector, horizontal)
        // Up x East = North: only mzPrime is required for the camera -Z North component
        final mzPrime = ax * hy - ay * hx;

        // Camera pointing direction is -Z of device in portrait.
        // In the East-North horizontal plane:
        // East component = -Z . H = -hz
        // North component = -Z . M' = -mzPrime
        final rawAzimuth = math.atan2(-hz, -mzPrime);

        // Circular exponential moving average to prevent 0 <-> 2pi wrap-around jitter
        _headingRadians = _filterCircularAngle(_headingRadians, rawAzimuth, filterSmoothing);
      }
    }

    _notifyListeners();
  }

  /// Smooths circular angles taking the shortest arc across 0 <-> 2pi.
  static double _filterCircularAngle(double current, double target, double alpha) {
    var diff = target - current;
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    return _normalizeAngle(current + alpha * diff);
  }

  /// Normalizes angle to [0, 2*pi).
  static double _normalizeAngle(double angle) {
    var a = angle % (2 * math.pi);
    if (a < 0) a += 2 * math.pi;
    return a;
  }
}
