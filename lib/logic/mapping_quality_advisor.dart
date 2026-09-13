import '../models/node.dart';

enum AlertType {
  lowLight,
  walkingTooFast,
  badTilt,
  featurelessSurface,
  tooCloseToNode,
  loopClosureAvailable,
  trackingLost,
  readyToMap,
}

enum AlertSeverity { info, warning, danger, success }

class AdvisorAlert {
  final AlertType type;
  final String message;
  final AlertSeverity severity;
  final String? actionLabel;
  final MapNode? targetNode;

  const AdvisorAlert({
    required this.type,
    required this.message,
    required this.severity,
    this.actionLabel,
    this.targetNode,
  });
}

/// Real-time environmental and tracking quality advisor for building admins during mapping.
/// Evaluates camera luminance, motion velocity, device tilt, and spatial proximity.
class MappingQualityAdvisor {
  double _lastLuminance = 128.0;
  double _lastLumaVariance = 30.0;
  double _currentSpeedMps = 0.0;
  double _phonePitchDeg = 45.0; // 0 = flat down, 90 = vertical horizon
  bool _isTrackingLost = false;

  // Thresholds
  static const double lowLightThreshold = 38.0;
  static const double lowContrastThreshold = 7.0;
  static const double maxWalkingSpeedMps = 1.8;
  static const double minDistanceThresholdM = 0.8;

  // Getters for telemetry
  double get lastLuminance => _lastLuminance;
  double get currentSpeedMps => _currentSpeedMps;
  double get phonePitchDeg => _phonePitchDeg;
  bool get isTrackingLost => _isTrackingLost;

  /// Updates camera lighting & contrast metrics from live frame analysis.
  void updateCameraMetrics({required double averageLuminance, double variance = 30.0}) {
    _lastLuminance = averageLuminance;
    _lastLumaVariance = variance;
  }

  /// Updates motion speed (meters per second) and pitch tilt (degrees).
  void updateMotionMetrics({required double speedMps, double pitchDeg = 45.0}) {
    _currentSpeedMps = speedMps;
    _phonePitchDeg = pitchDeg;
  }

  /// Updates tracking state (e.g. ARCore trackable status).
  void setTrackingLost(bool lost) {
    _isTrackingLost = lost;
  }

  /// Evaluates all conditions and returns the most urgent advisory alert, if any.
  AdvisorAlert? evaluate({
    required double distanceFromLastNode,
    required int nodeCount,
    MapNode? loopCandidate,
    double? loopCandidateDistance,
  }) {
    // 1. Critical: Tracking Lost
    if (_isTrackingLost) {
      return const AdvisorAlert(
        type: AlertType.trackingLost,
        message: 'Tracking Lost: Move phone slowly across floor to recalibrate.',
        severity: AlertSeverity.danger,
      );
    }

    // 2. High priority: Low Light Area
    if (_lastLuminance < lowLightThreshold) {
      return const AdvisorAlert(
        type: AlertType.lowLight,
        message: 'Low Light Area: Visual tracking may degrade. Turn on flashlight.',
        severity: AlertSeverity.warning,
        actionLabel: 'Torch On',
      );
    }

    // 3. High priority: Walking Too Fast
    if (_currentSpeedMps > maxWalkingSpeedMps) {
      return AdvisorAlert(
        type: AlertType.walkingTooFast,
        message: 'Walking Too Fast (${_currentSpeedMps.toStringAsFixed(1)} m/s): Slow down for accurate distance.',
        severity: AlertSeverity.warning,
      );
    }

    // 4. Proximity: Loop Closure Detected
    if (loopCandidate != null && loopCandidateDistance != null && loopCandidateDistance <= 2.5) {
      return AdvisorAlert(
        type: AlertType.loopClosureAvailable,
        message: 'Near "${loopCandidate.label}" (${loopCandidateDistance.toStringAsFixed(1)}m). Connect corridor loop?',
        severity: AlertSeverity.success,
        actionLabel: 'Link Loop',
        targetNode: loopCandidate,
      );
    }

    // 5. Anti-Collision: Too close to previous node
    if (nodeCount > 0 && distanceFromLastNode < minDistanceThresholdM) {
      return AdvisorAlert(
        type: AlertType.tooCloseToNode,
        message: 'Only ${distanceFromLastNode.toStringAsFixed(1)}m from previous node. Walk forward before placing.',
        severity: AlertSeverity.info,
      );
    }

    // 6. Camera Tilt Warning
    if (_phonePitchDeg > 75.0) {
      return const AdvisorAlert(
        type: AlertType.badTilt,
        message: 'Angle Phone Down: Aim camera at the floor 2-3m ahead.',
        severity: AlertSeverity.info,
      );
    } else if (_phonePitchDeg < 15.0) {
      return const AdvisorAlert(
        type: AlertType.badTilt,
        message: 'Angle Phone Forward: Do not point directly straight down at feet.',
        severity: AlertSeverity.info,
      );
    }

    // 7. Featureless surface / blank wall
    if (_lastLumaVariance < lowContrastThreshold) {
      return const AdvisorAlert(
        type: AlertType.featurelessSurface,
        message: 'Low Visual Contrast: Aim at door frames, floor seams, or signs.',
        severity: AlertSeverity.info,
      );
    }

    return null;
  }
}
