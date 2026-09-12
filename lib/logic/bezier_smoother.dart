import 'dart:math' as math;

import '../models/node.dart';
import '../native/ar_bridge.dart';

/// A smoothed 3D waypoint along the navigation path, optimized for placing
/// AR directional arrows and calculating turn-by-turn guidance prompts.
class SmoothedPathPoint {
  /// 3D position in the floor coordinate space (meters, y = vertical height).
  final Vector3 position;

  /// Horizontal heading angle in degrees (0° = +Z, clockwise positive).
  final double yawDegrees;

  /// Cumulative distance along the smoothed path from the starting point.
  final double distanceAlongPath;

  /// Whether this point represents an original graph node (e.g., junction, room).
  final bool isKeyWaypoint;

  /// Label of the waypoint if this is a key node.
  final String? waypointLabel;

  /// Turn guidance instruction at this waypoint (e.g. 'Turn Left', 'Continue Straight').
  final String? turnInstruction;

  const SmoothedPathPoint({
    required this.position,
    required this.yawDegrees,
    required this.distanceAlongPath,
    this.isKeyWaypoint = false,
    this.waypointLabel,
    this.turnInstruction,
  });

  Map<String, dynamic> toMap() => {
        'x': position.x,
        'y': position.y,
        'z': position.z,
        'yaw': yawDegrees,
        'distance': distanceAlongPath,
        'isKeyWaypoint': isKeyWaypoint,
        'label': waypointLabel,
        'instruction': turnInstruction,
      };
}

/// Turn instruction detail for high-level HUD cards.
class TurnInstruction {
  final String nodeLabel;
  final String instruction; // 'Start', 'Turn Left', 'Turn Right', 'Continue Straight', 'Arrive'
  final double distanceToTurn;
  final Vector3 position;

  const TurnInstruction({
    required this.nodeLabel,
    required this.instruction,
    required this.distanceToTurn,
    required this.position,
  });
}

/// Engine for smoothing discrete A* path graph waypoints into continuous,
/// curved paths using quadratic Bezier curves with corridor wall-safety clamping.
class BezierSmoother {
  /// Default spacing between successive AR arrows along the path (meters).
  static const double defaultStepDistance = 0.75;

  /// Default height above floor for floating AR arrows (meters).
  static const double defaultArrowHeight = 0.75;

  /// Maximum radius for corridor turns to ensure curves stay strictly within
  /// walkable hallway boundaries without clipping into corner walls.
  static const double maxCornerRadius = 1.0;

  /// Smooths a list of [MapNode] waypoints into a continuous sequence of
  /// [SmoothedPathPoint]s.
  static List<SmoothedPathPoint> smoothPath(
    List<MapNode> nodes, {
    double stepDistance = defaultStepDistance,
    double heightOffset = defaultArrowHeight,
    double cornerRadius = maxCornerRadius,
  }) {
    if (nodes.isEmpty) return const [];

    if (nodes.length == 1) {
      final pos = nodes.first.position;
      return [
        SmoothedPathPoint(
          position: Vector3(pos.x, pos.y + heightOffset, pos.z),
          yawDegrees: 0,
          distanceAlongPath: 0,
          isKeyWaypoint: true,
          waypointLabel: nodes.first.label,
          turnInstruction: 'Arrive at ${nodes.first.label}',
        ),
      ];
    }

    // Convert MapNodes into raw 3D vectors
    final rawPoints = nodes
        .map((n) => Vector3(n.position.x, n.position.y, n.position.z))
        .toList();

    // 1. Generate smoothed 3D polyline using quadratic Bezier curves at corners
    final curvePoints = _generateContinuousCurve(
      rawPoints,
      stepDistance: stepDistance,
      maxRadius: cornerRadius,
    );

    if (curvePoints.isEmpty) return const [];

    // 2. Sample along the curve at uniform intervals and apply eye-level height
    final smoothedPoints = <SmoothedPathPoint>[];
    double totalDistance = 0;

    for (int i = 0; i < curvePoints.length; i++) {
      final current = curvePoints[i];
      if (i > 0) {
        final prev = curvePoints[i - 1];
        final dx = current.x - prev.x;
        final dy = current.y - prev.y;
        final dz = current.z - prev.z;
        totalDistance += math.sqrt(dx * dx + dy * dy + dz * dz);
      }

      // Compute heading/yaw facing towards next point
      double yaw = 0;
      if (i < curvePoints.length - 1) {
        final next = curvePoints[i + 1];
        final dx = next.x - current.x;
        final dz = next.z - current.z;
        yaw = math.atan2(dx, dz) * 180 / math.pi;
      } else if (i > 0) {
        final prev = curvePoints[i - 1];
        final dx = current.x - prev.x;
        final dz = current.z - prev.z;
        yaw = math.atan2(dx, dz) * 180 / math.pi;
      }

      // Identify if point is close to one of the original nodes
      MapNode? matchedNode;
      for (final n in nodes) {
        final dist = _distance2D(current.x, current.z, n.position.x, n.position.z);
        if (dist <= stepDistance * 0.6) {
          matchedNode = n;
          break;
        }
      }

      smoothedPoints.add(
        SmoothedPathPoint(
          position: Vector3(current.x, current.y + heightOffset, current.z),
          yawDegrees: yaw,
          distanceAlongPath: totalDistance,
          isKeyWaypoint: matchedNode != null,
          waypointLabel: matchedNode?.label,
        ),
      );
    }

    return smoothedPoints;
  }

  /// Extracts structured turn-by-turn instructions from the path nodes.
  static List<TurnInstruction> extractTurnInstructions(List<MapNode> nodes) {
    if (nodes.isEmpty) return const [];
    if (nodes.length == 1) {
      return [
        TurnInstruction(
          nodeLabel: nodes.first.label,
          instruction: 'You are at ${nodes.first.label}',
          distanceToTurn: 0,
          position: Vector3(
            nodes.first.position.x,
            nodes.first.position.y,
            nodes.first.position.z,
          ),
        ),
      ];
    }

    final instructions = <TurnInstruction>[];
    double cumulativeDistance = 0;

    // First node instruction: Start
    instructions.add(
      TurnInstruction(
        nodeLabel: nodes.first.label,
        instruction: 'Start from ${nodes.first.label}',
        distanceToTurn: 0,
        position: Vector3(
          nodes.first.position.x,
          nodes.first.position.y,
          nodes.first.position.z,
        ),
      ),
    );

    for (int i = 1; i < nodes.length - 1; i++) {
      final prev = nodes[i - 1].position;
      final curr = nodes[i].position;
      final next = nodes[i + 1].position;

      final segDist = curr.distanceTo(prev);
      cumulativeDistance += segDist;

      // Vectors in the X-Z floor plane
      final inX = curr.x - prev.x;
      final inZ = curr.z - prev.z;
      final outX = next.x - curr.x;
      final outZ = next.z - curr.z;

      // 2D Cross product in X-Z determines left vs right turn
      // cross = inX * outZ - inZ * outX
      final cross = (inX * outZ) - (inZ * outX);
      final dot = (inX * outX) + (inZ * outZ);
      final inLen = math.sqrt(inX * inX + inZ * inZ);
      final outLen = math.sqrt(outX * outX + outZ * outZ);

      final cosAngle = inLen * outLen > 0 ? dot / (inLen * outLen) : 1.0;

      String action = 'Continue Straight';
      if (cosAngle < 0.95) {
        // Significant turn detected
        if (cross > 0.05) {
          action = 'Turn Left';
        } else if (cross < -0.05) {
          action = 'Turn Right';
        }
      }

      instructions.add(
        TurnInstruction(
          nodeLabel: nodes[i].label,
          instruction: '$action at ${nodes[i].label}',
          distanceToTurn: cumulativeDistance,
          position: Vector3(curr.x, curr.y, curr.z),
        ),
      );
    }

    // Final destination
    final last = nodes.last;
    final prevToLast = nodes[nodes.length - 2];
    cumulativeDistance += last.position.distanceTo(prevToLast.position);

    instructions.add(
      TurnInstruction(
        nodeLabel: last.label,
        instruction: 'Arrive at ${last.label}',
        distanceToTurn: cumulativeDistance,
        position: Vector3(last.position.x, last.position.y, last.position.z),
      ),
    );

    return instructions;
  }

  /// Internal generator creating a smooth curve through waypoints.
  static List<Vector3> _generateContinuousCurve(
    List<Vector3> waypoints, {
    required double stepDistance,
    required double maxRadius,
  }) {
    if (waypoints.length < 2) return waypoints;

    if (waypoints.length == 2) {
      return _interpolateSegment(waypoints[0], waypoints[1], stepDistance);
    }

    final points = <Vector3>[];

    Vector3 currentSegmentStart = waypoints[0];

    for (int i = 1; i < waypoints.length - 1; i++) {
      final prev = waypoints[i - 1];
      final corner = waypoints[i];
      final next = waypoints[i + 1];

      final inVector = _subtract(corner, prev);
      final outVector = _subtract(next, corner);

      final inLen = _length(inVector);
      final outLen = _length(outVector);

      if (inLen == 0 || outLen == 0) continue;

      // Adaptive corner radius: clamp to at most 35% of adjacent segment lengths
      // to ensure curve stays well inside corridor boundaries and avoids wall clipping
      final radius = math.min(
        maxRadius,
        math.min(inLen * 0.35, outLen * 0.35),
      );

      // Curve start and end control points
      final pStart = _add(
        corner,
        _scale(inVector, -radius / inLen),
      );
      final pEnd = _add(
        corner,
        _scale(outVector, radius / outLen),
      );

      // Interpolate straight section from currentSegmentStart to pStart
      final straightSegment = _interpolateSegment(
        currentSegmentStart,
        pStart,
        stepDistance,
      );
      if (points.isEmpty) {
        points.addAll(straightSegment);
      } else if (straightSegment.isNotEmpty) {
        // Avoid duplicating connecting point
        points.addAll(straightSegment.sublist(1));
      }

      // Interpolate quadratic Bezier curve around the corner
      final curveSegment = _interpolateQuadraticBezier(
        pStart,
        corner,
        pEnd,
        stepDistance,
      );
      if (curveSegment.isNotEmpty) {
        points.addAll(curveSegment.sublist(1));
      }

      currentSegmentStart = pEnd;
    }

    // Final straight segment to destination
    final lastStraight = _interpolateSegment(
      currentSegmentStart,
      waypoints.last,
      stepDistance,
    );
    if (points.isEmpty) {
      points.addAll(lastStraight);
    } else if (lastStraight.isNotEmpty) {
      points.addAll(lastStraight.sublist(1));
    }

    return points;
  }

  static List<Vector3> _interpolateSegment(
    Vector3 start,
    Vector3 end,
    double stepDistance,
  ) {
    final dist = _distance3D(start, end);
    if (dist <= 0.001) return [start];

    final count = (dist / stepDistance).ceil();
    final result = <Vector3>[];

    for (int i = 0; i <= count; i++) {
      final t = i / count;
      result.add(
        Vector3(
          start.x + (end.x - start.x) * t,
          start.y + (end.y - start.y) * t,
          start.z + (end.z - start.z) * t,
        ),
      );
    }
    return result;
  }

  static List<Vector3> _interpolateQuadraticBezier(
    Vector3 p0,
    Vector3 p1,
    Vector3 p2,
    double stepDistance,
  ) {
    // Approximate curve length by chord sum
    final approxLength = _distance3D(p0, p1) + _distance3D(p1, p2);
    final count = math.max(3, (approxLength / stepDistance).ceil());
    final result = <Vector3>[];

    for (int i = 0; i <= count; i++) {
      final t = i / count;
      final invT = 1.0 - t;
      // B(t) = (1-t)^2 * P0 + 2(1-t)t * P1 + t^2 * P2
      final x = (invT * invT * p0.x) + (2 * invT * t * p1.x) + (t * t * p2.x);
      final y = (invT * invT * p0.y) + (2 * invT * t * p1.y) + (t * t * p2.y);
      final z = (invT * invT * p0.z) + (2 * invT * t * p1.z) + (t * t * p2.z);

      result.add(Vector3(x, y, z));
    }
    return result;
  }

  static double _distance2D(double x1, double z1, double x2, double z2) {
    final dx = x1 - x2;
    final dz = z1 - z2;
    return math.sqrt(dx * dx + dz * dz);
  }

  static double _distance3D(Vector3 a, Vector3 b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  static Vector3 _add(Vector3 a, Vector3 b) =>
      Vector3(a.x + b.x, a.y + b.y, a.z + b.z);

  static Vector3 _subtract(Vector3 a, Vector3 b) =>
      Vector3(a.x - b.x, a.y - b.y, a.z - b.z);

  static Vector3 _scale(Vector3 a, double factor) =>
      Vector3(a.x * factor, a.y * factor, a.z * factor);

  static double _length(Vector3 a) =>
      math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}
