import 'dart:math' as math;

import '../models/node.dart';

/// Point in the breadcrumb trail walked by the admin.
class BreadcrumbPoint {
  final Position position;
  final DateTime timestamp;

  const BreadcrumbPoint({required this.position, required this.timestamp});
}

/// Continuous spatial odometry & pedestrian dead reckoning (PDR) engine
/// for indoor mapping without GPS.
///
/// Tracks the admin's physical translation in world coordinates (meters)
/// relative to the floor anchor, records footsteps, maintains breadcrumb trails,
/// and detects proximity to existing nodes for loop closure.
class SpatialOdometryTracker {
  SpatialOdometryTracker({
    this.strideLengthMeters = 0.72,
    Position? initialPosition,
    double initialHeadingRadians = 0.0,
    this.isRecording = true,
  })  : _currentPosition = initialPosition ?? const Position(x: 0, y: 0, z: 0),
        _headingRadians = initialHeadingRadians;

  /// Stride length in meters (default 0.72m).
  double strideLengthMeters;

  /// Whether active path tracking is recording.
  /// When false, accidental steps and movement are ignored.
  bool isRecording;

  Position _currentPosition;
  double _headingRadians; // 0 = +Z forward, pi/2 = +X right

  Position? _lastPlacedNodePosition;
  int _totalSteps = 0;
  int _stepsSinceLastNode = 0;
  double _totalDistanceWalked = 0.0;

  final List<BreadcrumbPoint> _breadcrumbTrail = [];

  // Getters
  Position get currentPosition => _currentPosition;
  double get headingRadians => _headingRadians;
  double get headingDegrees => (_headingRadians * 180 / math.pi) % 360;
  int get totalSteps => _totalSteps;
  int get stepsSinceLastNode => _stepsSinceLastNode;
  double get totalDistanceWalked => _totalDistanceWalked;
  List<BreadcrumbPoint> get breadcrumbTrail => List.unmodifiable(_breadcrumbTrail);

  void startRecording() => isRecording = true;
  void pauseRecording() => isRecording = false;
  void toggleRecording() => isRecording = !isRecording;

  /// Distance from the last placed node in meters.
  double get distanceFromLastNode {
    if (_lastPlacedNodePosition == null) return _totalDistanceWalked;
    final dx = _currentPosition.x - _lastPlacedNodePosition!.x;
    final dz = _currentPosition.z - _lastPlacedNodePosition!.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  /// Sets the reference anchor when the first node is dropped or loaded.
  void setLastPlacedNode(MapNode? node) {
    if (node != null) {
      _lastPlacedNodePosition = node.position;
      _stepsSinceLastNode = 0;
      _addBreadcrumb(node.position);
    } else {
      _lastPlacedNodePosition = null;
      _stepsSinceLastNode = 0;
    }
  }

  /// Updates heading in radians.
  void setHeading(double radians) {
    _headingRadians = radians;
  }

  /// Updates heading by rotating by delta radians.
  void rotateHeading(double deltaRadians) {
    _headingRadians += deltaRadians;
  }

  /// Direct pose update from hardware AR / VIO (if available from native layer).
  void updateUserPose(double x, double y, double z, {bool force = false}) {
    if (!isRecording && !force) return;
    final newPos = Position(x: x, y: y, z: z);
    final distDelta = _currentPosition.distanceTo(newPos);
    if (distDelta > 0.02) {
      _totalDistanceWalked += distDelta;
      _currentPosition = newPos;
      _addBreadcrumb(newPos);
    }
  }

  /// Records a physical footstep detected by accelerometer/PDR or manual stride.
  /// Advances current position along the current heading vector by [strideLengthMeters].
  Position recordStep({double? customStride, bool force = false}) {
    if (!isRecording && !force) return _currentPosition;
    final stride = customStride ?? strideLengthMeters;
    _totalSteps++;
    _stepsSinceLastNode++;
    _totalDistanceWalked += stride;

    // Movement vector along heading
    // sin(heading) gives X displacement, cos(heading) gives Z displacement
    final dx = stride * math.sin(_headingRadians);
    final dz = stride * math.cos(_headingRadians);

    _currentPosition = Position(
      x: double.parse((_currentPosition.x + dx).toStringAsFixed(2)),
      y: 0.0,
      z: double.parse((_currentPosition.z + dz).toStringAsFixed(2)),
    );

    _addBreadcrumb(_currentPosition);
    return _currentPosition;
  }

  /// Manually advance distance forward along current heading (e.g. simulation or stepper).
  Position advanceDistance(double distanceMeters, {bool force = false}) {
    if (!isRecording && !force) return _currentPosition;
    _totalDistanceWalked += distanceMeters;
    final dx = distanceMeters * math.sin(_headingRadians);
    final dz = distanceMeters * math.cos(_headingRadians);

    _currentPosition = Position(
      x: double.parse((_currentPosition.x + dx).toStringAsFixed(2)),
      y: 0.0,
      z: double.parse((_currentPosition.z + dz).toStringAsFixed(2)),
    );

    _addBreadcrumb(_currentPosition);
    return _currentPosition;
  }

  /// Calculates the suggested node position.
  /// If [manualDistanceOverride] is specified and a previous node exists,
  /// snaps the position to exact distance from the previous node along current heading.
  Position calculateNodePosition({
    double forwardOffsetMeters = 0.0,
    double? manualDistanceOverride,
  }) {
    if (manualDistanceOverride != null && _lastPlacedNodePosition != null) {
      // Calculate unit vector from last node to current position, or along heading
      double dirX = math.sin(_headingRadians);
      double dirZ = math.cos(_headingRadians);

      final diffX = _currentPosition.x - _lastPlacedNodePosition!.x;
      final diffZ = _currentPosition.z - _lastPlacedNodePosition!.z;
      final currentDist = math.sqrt(diffX * diffX + diffZ * diffZ);

      if (currentDist > 0.1) {
        dirX = diffX / currentDist;
        dirZ = diffZ / currentDist;
      }

      return Position(
        x: double.parse((_lastPlacedNodePosition!.x + dirX * manualDistanceOverride).toStringAsFixed(2)),
        y: 0.0,
        z: double.parse((_lastPlacedNodePosition!.z + dirZ * manualDistanceOverride).toStringAsFixed(2)),
      );
    }

    if (forwardOffsetMeters > 0) {
      final dx = forwardOffsetMeters * math.sin(_headingRadians);
      final dz = forwardOffsetMeters * math.cos(_headingRadians);
      return Position(
        x: double.parse((_currentPosition.x + dx).toStringAsFixed(2)),
        y: 0.0,
        z: double.parse((_currentPosition.z + dz).toStringAsFixed(2)),
      );
    }

    return _currentPosition;
  }

  /// Anti-collision guard: checks if proposed or current position is too close (< minThreshold)
  /// to the last placed node to prevent duplicate/stacked nodes.
  bool isTooCloseToLastNode({Position? targetPosition, double minThresholdMeters = 0.8}) {
    if (_lastPlacedNodePosition == null) return false;
    final pos = targetPosition ?? _currentPosition;
    final dist = _lastPlacedNodePosition!.distanceTo(pos);
    return dist < minThresholdMeters;
  }

  /// Detects if current position is near an existing node on the floor (< thresholdMeters)
  /// for automatic loop closure linking (excluding the immediate previous node).
  MapNode? checkLoopClosureCandidate(
    List<MapNode> existingNodes, {
    double thresholdMeters = 2.5,
    String? excludeNodeId,
  }) {
    if (existingNodes.length < 3) return null;

    MapNode? bestMatch;
    double minDistance = double.infinity;

    for (final node in existingNodes) {
      if (node.id == excludeNodeId || node.position == _lastPlacedNodePosition) {
        continue;
      }
      final dist = _currentPosition.distanceTo(node.position);
      if (dist <= thresholdMeters && dist < minDistance) {
        minDistance = dist;
        bestMatch = node;
      }
    }

    return bestMatch;
  }

  /// Resets tracker state for a fresh floor mapping session.
  void reset({Position? origin}) {
    _currentPosition = origin ?? const Position(x: 0, y: 0, z: 0);
    _lastPlacedNodePosition = null;
    _totalSteps = 0;
    _stepsSinceLastNode = 0;
    _totalDistanceWalked = 0.0;
    _breadcrumbTrail.clear();
  }

  /// Explicitly clears breadcrumbs.
  void clearBreadcrumbs() {
    _breadcrumbTrail.clear();
  }

  void _addBreadcrumb(Position pos) {
    if (_breadcrumbTrail.isNotEmpty) {
      final last = _breadcrumbTrail.last.position;
      final d = math.sqrt(
        (pos.x - last.x) * (pos.x - last.x) + (pos.z - last.z) * (pos.z - last.z),
      );
      if (d < 0.2) return; // Don't spam breadcrumbs for tiny jitter
    }

    _breadcrumbTrail.add(
      BreadcrumbPoint(position: pos, timestamp: DateTime.now()),
    );
    if (_breadcrumbTrail.length > 500) {
      _breadcrumbTrail.removeAt(0);
    }
  }
}
