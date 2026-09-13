import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../logic/bezier_smoother.dart';
import '../../models/node.dart';
import '../../native/ar_bridge.dart';

/// AR Perspective Simulation View:
/// Renders a dynamic 3D-perspective view with animated floating
/// directional chevrons, 3D starting point marker icon, 3D destination marker icon,
/// and floor turn indicators following the Bezier curve.
class ArPerspectiveSimulationView extends StatelessWidget {
  final List<SmoothedPathPoint> smoothedPoints;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final MapNode destination;
  final MapNode? startNode;
  final double animationProgress;
  final Vector3? userPosition;
  final double? cameraHeadingRadians;
  final double? cameraPitchRadians;
  final double? cameraRollRadians;
  final bool isOverlay;
  final bool hasReachedDestination;
  final List<Position>? walkedBreadcrumbs;

  const ArPerspectiveSimulationView({
    super.key,
    required this.smoothedPoints,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    required this.destination,
    this.startNode,
    required this.animationProgress,
    this.userPosition,
    this.cameraHeadingRadians,
    this.cameraPitchRadians,
    this.cameraRollRadians,
    this.isOverlay = false,
    this.hasReachedDestination = false,
    this.walkedBreadcrumbs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isOverlay ? Colors.transparent : const Color(0xFF070B14),
      child: CustomPaint(
        painter: ArPerspectivePainter(
          points: smoothedPoints,
          turnInstructions: turnInstructions,
          activeStep: currentInstructionIndex,
          animationProgress: animationProgress,
          destination: destination,
          startNode: startNode,
          userPosition: userPosition,
          cameraHeadingRadians: cameraHeadingRadians,
          cameraPitchRadians: cameraPitchRadians,
          cameraRollRadians: cameraRollRadians,
          isOverlay: isOverlay,
          hasReachedDestination: hasReachedDestination,
          walkedBreadcrumbs: walkedBreadcrumbs,
        ),
        child: isOverlay
            ? const SizedBox.expand()
            : Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.cube_box,
                      color: Colors.white12,
                      size: 64,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AR Guidance View Active',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start & Destination beacons rendered in 3D perspective',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Custom painter simulating perspective AR guidance arrows on the floor.
/// Computes accurate 3D corridor perspective projection from camera anchor,
/// rendering directional flowing chevrons, 3D AR start icon marker,
/// 3D AR destination pin marker, and floating badges.
class ArPerspectivePainter extends CustomPainter {
  final List<SmoothedPathPoint> points;
  final List<TurnInstruction> turnInstructions;
  final int activeStep;
  final double animationProgress;
  final MapNode destination;
  final MapNode? startNode;
  final Vector3? userPosition;
  final double? cameraHeadingRadians;
  final double? cameraPitchRadians;
  final double? cameraRollRadians;
  final bool isOverlay;
  final bool hasReachedDestination;
  final List<Position>? walkedBreadcrumbs;

  ArPerspectivePainter({
    required this.points,
    required this.turnInstructions,
    required this.activeStep,
    required this.animationProgress,
    required this.destination,
    this.startNode,
    this.userPosition,
    this.cameraHeadingRadians,
    this.cameraPitchRadians,
    this.cameraRollRadians,
    this.isOverlay = false,
    this.hasReachedDestination = false,
    this.walkedBreadcrumbs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final originX = width * 0.5;
    final originY = height * 0.5;

    final pitch = cameraPitchRadians ?? -0.45;
    final roll = cameraRollRadians ?? 0.0;
    const double cameraHeight = 1.35;

    // True physical camera focal length for portrait camera viewfinder:
    const fovV = 60.0 * math.pi / 180.0;
    final focalLength = (height * 0.5) / math.tan(fovV * 0.5);

    // Dynamic horizon line based on camera pitch
    final horizonY = originY - math.tan(pitch) * focalLength;
    final groundBaselineY = height * 0.82;

    // 1. Draw floor grid when in standalone simulation mode
    if (!isOverlay) {
      final floorGradient = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B14), Color(0xFF0F172A)],
        ).createShader(Rect.fromLTWH(0, horizonY.clamp(0.0, height), width, height));
      canvas.drawRect(Rect.fromLTWH(0, horizonY.clamp(0.0, height), width, height), floorGradient);

      final horizonPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.25)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, horizonY), Offset(width, horizonY), horizonPaint);

      final gridPaint = Paint()
        ..color = Colors.cyan.withValues(alpha: 0.08)
        ..strokeWidth = 1.0;

      for (double x = 0; x <= width; x += width / 8) {
        canvas.drawLine(Offset(originX, horizonY), Offset(x, height), gridPaint);
      }
      for (double y = horizonY; y <= height; y += (height - horizonY) / 6) {
        canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
      }
    }

    if (points.isEmpty && startNode == null) return;

    // 2. Camera anchor position and forward direction
    final Vector3 anchorPos = userPosition ??
        (activeStep < turnInstructions.length
            ? turnInstructions[activeStep].position
            : (points.isNotEmpty
                ? points.first.position
                : (startNode != null
                    ? Vector3(startNode!.position.x, startNode!.position.y, startNode!.position.z)
                    : const Vector3(0, 0, 0))));

    // Find closest smoothed point to current anchor
    int startIdx = 0;
    if (points.isNotEmpty) {
      double minD = double.infinity;
      for (int i = 0; i < points.length; i++) {
        final p = points[i].position;
        final d = (p.x - anchorPos.x) * (p.x - anchorPos.x) + (p.z - anchorPos.z) * (p.z - anchorPos.z);
        if (d < minD) {
          minD = d;
          startIdx = i;
        }
      }
    }

    // Determine camera heading in world space
    final double heading;
    if (cameraHeadingRadians != null) {
      heading = cameraHeadingRadians!;
    } else if (points.isNotEmpty && startIdx < points.length - 1) {
      final lookAhead = math.min(startIdx + 4, points.length - 1);
      final pNext = points[lookAhead].position;
      final dx = pNext.x - points[startIdx].position.x;
      final dz = pNext.z - points[startIdx].position.z;
      heading = math.atan2(dx, dz);
    } else {
      heading = 0.0;
    }

    final cosH = math.cos(heading);
    final sinH = math.sin(heading);
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final cosR = math.cos(roll);
    final sinR = math.sin(roll);

    // Forward vector (through camera optical axis)
    final fx = sinH * cosP;
    final fy = sinP;
    final fz = cosH * cosP;

    // Unrolled Right vector (horizontal right)
    final r0x = cosH;
    final r0y = 0.0;
    final r0z = -sinH;

    // Unrolled Up vector (perpendicular to F and r0)
    final u0x = -sinH * sinP;
    final u0y = cosP;
    final u0z = -cosH * sinP;

    // Camera Right vector (X_c) incorporating device wrist roll
    final rx = r0x * cosR + u0x * sinR;
    final ry = r0y * cosR + u0y * sinR;
    final rz = r0z * cosR + u0z * sinR;

    // Camera Up vector (Y_c) incorporating device wrist roll
    final ux = -r0x * sinR + u0x * cosR;
    final uy = -r0y * sinR + u0y * cosR;
    final uz = -r0z * sinR + u0z * cosR;

    // Perspective projection function from 3D world meters into 2D screen coordinates
    // Returns null if point is behind the camera viewpoint (zCam <= 0.15m)
    Offset? project(Vector3 pos) {
      final dx = pos.x - anchorPos.x;
      final dy = pos.y - cameraHeight;
      final dz = pos.z - anchorPos.z;

      final zCam = dx * fx + dy * fy + dz * fz;
      if (zCam < 0.15) return null;

      final xCam = dx * rx + dy * ry + dz * rz;
      final yCam = dx * ux + dy * uy + dz * uz;

      final sx = originX + (xCam / zCam) * focalLength;
      final sy = originY - (yCam / zCam) * focalLength;

      return Offset(sx, sy);
    }

    final visiblePoints = points.isNotEmpty ? points.sublist(startIdx) : <SmoothedPathPoint>[];
    final screenOffsets = <Offset>[];
    for (final pt in visiblePoints) {
      final proj = project(pt.position);
      if (proj != null) screenOffsets.add(proj);
    }

    // 2.5 Draw 3D Breadcrumb Footsteps on Floor (Dropped dots along walked path)
    if (walkedBreadcrumbs != null && walkedBreadcrumbs!.isNotEmpty) {
      final trailGlow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.28)
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final trailLine = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.75)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final outerRingFill = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      final outerRingStroke = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke;

      final coreDot = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      Offset? prevOffset;
      for (int i = 0; i < walkedBreadcrumbs!.length; i++) {
        final b = walkedBreadcrumbs![i];
        final p = project(Vector3(b.x, 0.0, b.z));
        if (p == null) {
          prevOffset = null;
          continue;
        }

        // Draw trail connecting consecutive footsteps
        if (prevOffset != null) {
          canvas.drawLine(prevOffset, p, trailGlow);
          canvas.drawLine(prevOffset, p, trailLine);
        }
        prevOffset = p;

        final depthRatio = ((p.dy - horizonY) / (groundBaselineY - horizonY)).clamp(0.2, 1.25);
        final baseR = 5.0 * depthRatio;

        // Outer translucent floor ring
        canvas.drawCircle(p, baseR * 1.8, outerRingFill);
        outerRingStroke.strokeWidth = 1.2 * depthRatio;
        canvas.drawCircle(p, baseR * 1.8, outerRingStroke);

        // Core bright dot
        canvas.drawCircle(p, baseR * 0.9, coreDot);

        // Pulsing glow on the latest footstep
        if (i == walkedBreadcrumbs!.length - 1) {
          final pulseR = (baseR * 1.8) + (6.0 * depthRatio * animationProgress);
          final pulsePaint = Paint()
            ..color = const Color(0xFF00E5FF).withValues(alpha: (0.6 * (1.0 - animationProgress)).clamp(0.0, 0.6))
            ..strokeWidth = 1.5 * depthRatio
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(p, pulseR, pulsePaint);
        }
      }
    }

    // 3. Draw smoothed path glow line with depth-tapered width
    if (screenOffsets.length >= 2) {
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.28)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final linePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < screenOffsets.length - 1; i++) {
        final pA = screenOffsets[i];
        final pB = screenOffsets[i + 1];
        final avgY = (pA.dy + pB.dy) * 0.5;
        final depthRatio = ((avgY - horizonY) / (originY - horizonY)).clamp(0.12, 1.0);

        glowPaint.strokeWidth = (12.0 * depthRatio).clamp(3.0, 14.0);
        linePaint.strokeWidth = (3.5 * depthRatio).clamp(1.2, 3.5);

        canvas.drawLine(pA, pB, glowPaint);
        canvas.drawLine(pA, pB, linePaint);
      }

      // Draw subtle AR feature/tracking sparkle points like in real ARCore
      _drawTrackingFeatureDots(canvas, screenOffsets, horizonY, originY);
    }

    // 4. Draw dynamic corridor-spanning directional chevrons flat on the ground in 3D perspective
    if (visiblePoints.length >= 2) {
      final startDist = visiblePoints.first.distanceAlongPath;
      final endDist = visiblePoints.last.distanceAlongPath;
      final visibleMeters = endDist - startDist;

      final chevronDistances = <double>[];
      if (hasReachedDestination) {
        // Destination arrived - silence arrows
      } else if (visibleMeters > 0.4 && visibleMeters < 1.4) {
        chevronDistances.add(startDist + visibleMeters * 0.5);
      } else if (visibleMeters >= 1.4) {
        // Physically spaced: 1 chevron every ~1.5m
        const chevronInterval = 1.5;
        // Start 0.65m in front of camera anchor so chevron is comfortably in view on the ground
        for (double d = startDist + 0.65; d <= endDist - 0.35; d += chevronInterval) {
          chevronDistances.add(d);
        }
      } else if (screenOffsets.length >= 2) {
        // Fallback if distance metrics are near zero
        final count = (visiblePoints.length / 3).clamp(1, 8).toInt();
        for (int i = 0; i < count; i++) {
          final ratio = (i + 0.5) / count;
          chevronDistances.add(startDist + ratio * math.max(0.5, visibleMeters));
        }
      }

      for (final dist in chevronDistances) {
        final distRatio = visibleMeters > 0.01
            ? ((dist - startDist) / visibleMeters).clamp(0.0, 1.0)
            : 0.5;

        // Sample exact 3D position and smoothed tangent vector on ground plane
        final sample = _samplePathPositionAndTangent(visiblePoints, dist);
        final p = sample.position;
        final t = sample.tangent;

        // Perpendicular right vector on ground plane: R = (T_z, 0, -T_x)
        final rxFloor = t.z;
        final rzFloor = -t.x;

        // Camera perspective factor s at p
        final dx = p.x - anchorPos.x;
        final dz = p.z - anchorPos.z;
        final zCam = dx * fx + dz * fz;
        if (zCam < -0.2) continue; // Behind camera

        final s = 4.5 / (4.5 + math.max(0.0, zCam));

        // Realistic tapering: scale down slightly in 3D + optical perspective shrinking
        final taper = (0.52 + 0.48 * s).clamp(0.50, 1.0);
        final hw = 0.34 * taper;     // Half-width (0.17m far to 0.34m near)
        final lTip = 0.40 * taper;   // Length to apex (0.20m far to 0.40m near)
        final lBand = 0.17 * taper;  // Band thickness (0.085m far to 0.17m near)

        // 6 ground vertices in 3D world space (Y = p.y)
        final vTip = Vector3(p.x + t.x * lTip, p.y, p.z + t.z * lTip);
        final vRightFront = Vector3(p.x + rxFloor * hw, p.y, p.z + rzFloor * hw);
        final vRightBack = Vector3(p.x + rxFloor * hw - t.x * lBand, p.y, p.z + rzFloor * hw - t.z * lBand);
        final vNotch = Vector3(p.x + t.x * (lTip - lBand), p.y, p.z + t.z * (lTip - lBand));
        final vLeftBack = Vector3(p.x - rxFloor * hw - t.x * lBand, p.y, p.z - rzFloor * hw - t.z * lBand);
        final vLeftFront = Vector3(p.x - rxFloor * hw, p.y, p.z - rzFloor * hw);

        final pTip = project(vTip);
        final pRightFront = project(vRightFront);
        final pRightBack = project(vRightBack);
        final pNotch = project(vNotch);
        final pLeftBack = project(vLeftBack);
        final pLeftFront = project(vLeftFront);

        if (pTip == null ||
            pRightFront == null ||
            pRightBack == null ||
            pNotch == null ||
            pLeftBack == null ||
            pLeftFront == null) {
          continue;
        }

        if (pTip.dy < horizonY - 15 || pTip.dy > height + 60) continue;

        // Traveling light wave flowing towards the destination
        final pulsePhase = (distRatio * 3.2 - animationProgress * 2.2) % 1.0;
        final pulse = (0.72 + 0.28 * math.sin((pulsePhase + 1.0) % 1.0 * math.pi)).clamp(0.50, 1.0);
        final distanceFade = (s / 0.85).clamp(0.40, 1.0);
        final brightness = pulse * distanceFade;

        _draw3dFloorChevron(
          canvas: canvas,
          pTip: pTip,
          pRightFront: pRightFront,
          pRightBack: pRightBack,
          pNotch: pNotch,
          pLeftBack: pLeftBack,
          pLeftFront: pLeftFront,
          scale: s,
          brightness: brightness,
        );
      }

      // Draw AR floor plane tracking ring in the foreground
      if (screenOffsets.isNotEmpty) {
        final fgPos = screenOffsets.first;
        final reticlePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.32)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        final reticleGlow = Paint()
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;
        final reticleCenter = Offset(fgPos.dx - 85.0, math.min(height - 45.0, fgPos.dy + 35.0));
        canvas.drawCircle(reticleCenter, 22.0, reticleGlow);
        canvas.drawCircle(reticleCenter, 22.0, reticlePaint);
      }
    }

    // 5. Draw turn indicator arrows at each upcoming turn (Left, Right)
    for (int i = activeStep; i < turnInstructions.length; i++) {
      final inst = turnInstructions[i];
      final lower = inst.instruction.toLowerCase();
      if (lower.contains('start') || lower.contains('arrive')) continue;

      final pos = project(inst.position);
      if (pos == null) continue;
      if (pos.dy < horizonY - 30 || pos.dy > height + 40) continue;

      final depthRatio = ((pos.dy - horizonY) / (originY - horizonY)).clamp(0.3, 1.0);
      final isCurrent = i == activeStep;

      if (lower.contains('left')) {
        _drawTurnMarker(
          canvas: canvas,
          pos: pos,
          isLeft: true,
          label: 'TURN LEFT',
          distance: inst.distanceToTurn,
          scale: depthRatio,
          isCurrent: isCurrent,
        );
      } else if (lower.contains('right')) {
        _drawTurnMarker(
          canvas: canvas,
          pos: pos,
          isLeft: false,
          label: 'TURN RIGHT',
          distance: inst.distanceToTurn,
          scale: depthRatio,
          isCurrent: isCurrent,
        );
      }
    }

    // 6. Draw 3D AR Starting Point Marker & Departure Icon
    Vector3? startVec;
    if (startNode != null) {
      startVec = Vector3(startNode!.position.x, startNode!.position.y, startNode!.position.z);
    } else if (points.isNotEmpty) {
      startVec = points.first.position;
    }

    if (startVec != null) {
      final startPos = project(startVec);
      if (startPos != null && startPos.dy >= horizonY - 40 && startPos.dy <= height + 60) {
        final depthRatio = ((startPos.dy - horizonY) / (originY - horizonY)).clamp(0.25, 1.25);
        _drawStartMarker(
          canvas: canvas,
          pos: startPos,
          label: startNode?.label ?? 'Start',
          scale: depthRatio,
        );
      }
    }

    // 7. Draw 3D AR Destination Marker & Star Pin Icon
    final destVec = Vector3(destination.position.x, destination.position.y, destination.position.z);
    final destPos = project(destVec);
    if (destPos != null &&
        destPos.dx >= -40 &&
        destPos.dx <= width + 40 &&
        destPos.dy >= horizonY - 40 &&
        destPos.dy <= height + 60) {
      final depthRatio = ((destPos.dy - horizonY) / (originY - horizonY)).clamp(0.25, 1.25);
      _drawDestinationMarker(
        canvas: canvas,
        pos: destPos,
        label: destination.label,
        scale: depthRatio,
        hasReached: hasReachedDestination,
      );
    } else {
      // Off-screen destination cue: user turned camera away from destination
      final dxDest = destination.position.x - anchorPos.x;
      final dzDest = destination.position.z - anchorPos.z;
      final destDist = math.sqrt(dxDest * dxDest + dzDest * dzDest);
      if (destDist > 0.4) {
        final bearing = math.atan2(dxDest, dzDest);
        var relAngle = bearing - heading;
        while (relAngle < -math.pi) {
          relAngle += 2 * math.pi;
        }
        while (relAngle > math.pi) {
          relAngle -= 2 * math.pi;
        }
        _drawOffScreenDestCue(
          canvas: canvas,
          size: size,
          angleDelta: relAngle,
          distance: destDist,
          label: destination.label,
          hasReached: hasReachedDestination,
        );
      }
    }
  }

  /// Draws a high-fidelity 3D Start Marker in AR:
  /// - Emerald pulsating concentric radar rings on floor
  /// - Holographic vertical laser guideline
  /// - Floating 3D Start Pin Emblem with forward navigation departure arrow icon
  /// - Floating luminous "START • [Label]" badge
  void _drawStartMarker({
    required Canvas canvas,
    required Offset pos,
    required String label,
    required double scale,
  }) {
    const startColor = Color(0xFF10B981); // Emerald green

    // 1. Concentric pulsing radar ripple rings on floor
    final pulseRing = Paint()
      ..color = startColor.withValues(alpha: (0.5 * (1.0 - animationProgress)).clamp(0.0, 0.5))
      ..strokeWidth = 2.5 * scale
      ..style = PaintingStyle.stroke;

    final baseRing = Paint()
      ..color = startColor.withValues(alpha: 0.7)
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;

    final innerFill = Paint()
      ..color = startColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final pulseRadius = (16.0 + 12.0 * (1.0 - animationProgress)) * scale;
    canvas.drawCircle(pos, pulseRadius, pulseRing);
    canvas.drawCircle(pos, 14.0 * scale, baseRing);
    canvas.drawCircle(pos, 8.0 * scale, innerFill);

    // Floor crosshair ticks
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.5 * scale;
    canvas.drawLine(Offset(pos.dx - 18 * scale, pos.dy), Offset(pos.dx - 10 * scale, pos.dy), tickPaint);
    canvas.drawLine(Offset(pos.dx + 10 * scale, pos.dy), Offset(pos.dx + 18 * scale, pos.dy), tickPaint);
    canvas.drawLine(Offset(pos.dx, pos.dy - 18 * scale), Offset(pos.dx, pos.dy - 10 * scale), tickPaint);
    canvas.drawLine(Offset(pos.dx, pos.dy + 10 * scale), Offset(pos.dx, pos.dy + 18 * scale), tickPaint);

    // 2. Holographic vertical laser beam from floor to floating badge
    final badgeY = pos.dy - (64.0 * scale);
    final beamGlow = Paint()
      ..color = startColor.withValues(alpha: 0.3)
      ..strokeWidth = 6.0 * scale;
    final beamCore = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.8 * scale;
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 16 * scale), beamGlow);
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 16 * scale), beamCore);

    // 3. Floating 3D Start Pin Icon Emblem
    final emblemCenter = Offset(pos.dx, badgeY);
    final emblemRadius = 18.0 * scale;

    // Emblem outer glow
    final haloPaint = Paint()
      ..color = startColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(emblemCenter, emblemRadius + 3.0, haloPaint);

    // Emblem body
    final emblemBg = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF065F46),
          const Color(0xFF064E3B),
          const Color(0xFF0F172A),
        ],
      ).createShader(Rect.fromCircle(center: emblemCenter, radius: emblemRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(emblemCenter, emblemRadius, emblemBg);

    final emblemBorder = Paint()
      ..color = const Color(0xFF34D399)
      ..strokeWidth = 2.2 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(emblemCenter, emblemRadius, emblemBorder);

    // Crisp Vector Start Icon (Departure Arrow / Compass Triangle) inside emblem
    final iconPath = Path();
    final isz = 8.0 * scale;
    iconPath.moveTo(emblemCenter.dx, emblemCenter.dy - isz); // Top apex
    iconPath.lineTo(emblemCenter.dx - isz, emblemCenter.dy + isz * 0.8); // Bottom left
    iconPath.lineTo(emblemCenter.dx, emblemCenter.dy + isz * 0.3); // Inner notch
    iconPath.lineTo(emblemCenter.dx + isz, emblemCenter.dy + isz * 0.8); // Bottom right
    iconPath.close();

    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(iconPath, iconPaint);

    // 4. Floating Start Label Pill
    final labelY = badgeY - (28.0 * scale);
    final textSpan = TextSpan(
      children: [
        const TextSpan(
          text: 'START  ',
          style: TextStyle(
            color: Color(0xFF34D399),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
      style: TextStyle(
        fontSize: (11.0 * scale).clamp(9.0, 13.0),
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + (20.0 * scale);
    final pillHeight = textPainter.height + (10.0 * scale);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(pos.dx, labelY),
        width: pillWidth,
        height: pillHeight,
      ),
      Radius.circular(pillHeight / 2),
    );

    final pillBg = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final pillBorder = Paint()
      ..color = startColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.4 * scale
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(pillRect, pillBg);
    canvas.drawRRect(pillRect, pillBorder);
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, labelY - textPainter.height / 2),
    );
  }

  /// Draws a high-fidelity Big 3D Rotating Destination Marker in AR:
  /// - 360-degree rotating ground radar scan with perspective-projected floor rings
  /// - Towering volumetric vertical laser light column with rising energy sparks
  /// - Large 3D faceted crystal map pin rotating continuously around the vertical Y-axis
  /// - Dynamic lighting calculation on each rotating face (specular highlights vs. ambient shadow)
  /// - Dual 3D gyroscopic orbital rings with orbiting satellite beads
  /// - Floating 3D rotating star core inside the pin head
  /// - Floating luminous "★ DESTINATION • [Label]" or "★ ARRIVED" badge
  void _drawDestinationMarker({
    required Canvas canvas,
    required Offset pos,
    required String label,
    required double scale,
    bool hasReached = false,
  }) {
    final destColor = hasReached ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final accentColor = hasReached ? const Color(0xFF34D399) : const Color(0xFFF87171);
    final pinScale = scale * 1.65; // Big prominent 3D presence

    // Continuous 3D rotation angle
    final rotY = animationProgress * 2 * math.pi;

    // 1. Perspective-flattened floor radar & expanding ripple rings
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(1.0, 0.42); // 3D floor perspective tilt

    final pulseRadius = (32.0 + 20.0 * (1.0 - animationProgress)) * pinScale;
    final pulseRing = Paint()
      ..color = destColor.withValues(alpha: (0.6 * (1.0 - animationProgress)).clamp(0.0, 0.6))
      ..strokeWidth = 3.0 * pinScale
      ..style = PaintingStyle.stroke;

    final baseRing = Paint()
      ..color = destColor.withValues(alpha: 0.85)
      ..strokeWidth = 2.5 * pinScale
      ..style = PaintingStyle.stroke;

    final innerRing = Paint()
      ..color = destColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset.zero, pulseRadius, pulseRing);
    canvas.drawCircle(Offset.zero, 28.0 * pinScale, baseRing);
    canvas.drawCircle(Offset.zero, 16.0 * pinScale, innerRing);

    // Rotating 3D floor radar sweep beam
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          destColor.withValues(alpha: 0.0),
          destColor.withValues(alpha: 0.05),
          destColor.withValues(alpha: 0.45),
        ],
        transform: GradientRotation(rotY),
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 28.0 * pinScale))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, 28.0 * pinScale, sweepPaint);

    // Cardinal floor crosshair ticks
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.8 * pinScale;
    canvas.drawLine(Offset(-36 * pinScale, 0), Offset(-24 * pinScale, 0), tickPaint);
    canvas.drawLine(Offset(24 * pinScale, 0), Offset(36 * pinScale, 0), tickPaint);
    canvas.drawLine(Offset(0, -36 * pinScale), Offset(0, -24 * pinScale), tickPaint);
    canvas.drawLine(Offset(0, 24 * pinScale), Offset(0, 36 * pinScale), tickPaint);

    canvas.restore();

    // 2. Towering Volumetric Vertical Holographic Laser Pillar
    final badgeY = pos.dy - (88.0 * pinScale);

    final beamHaze = Paint()
      ..color = destColor.withValues(alpha: 0.22)
      ..strokeWidth = 18.0 * pinScale;
    final beamGlow = Paint()
      ..color = accentColor.withValues(alpha: 0.45)
      ..strokeWidth = 7.0 * pinScale;
    final beamCore = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = 2.0 * pinScale;

    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 34 * pinScale), beamHaze);
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 34 * pinScale), beamGlow);
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 34 * pinScale), beamCore);

    // Rising energy sparkles along the light beam
    final rand = math.Random(42);
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    for (int s = 0; s < 5; s++) {
      final sparkT = ((animationProgress + s / 5.0) % 1.0);
      final sy = pos.dy - sparkT * (pos.dy - (badgeY + 38 * pinScale));
      final sx = pos.dx + (rand.nextDouble() - 0.5) * 12.0 * pinScale;
      sparkPaint.color = Colors.white.withValues(alpha: (0.8 * (1.0 - sparkT)).clamp(0.0, 0.8));
      canvas.drawCircle(Offset(sx, sy), 2.0 * pinScale, sparkPaint);
    }

    final emblemCenter = Offset(pos.dx, badgeY);

    // 3. Back Half of Dual 3D Gyroscopic Orbital Rings (drawn behind the pin)
    _drawOrbitalRings(
      canvas: canvas,
      center: emblemCenter,
      radius: 36.0 * pinScale,
      tiltAngle: 0.45,
      rotY: rotY,
      color: accentColor,
      isBackHalf: true,
      scale: pinScale,
    );
    _drawOrbitalRings(
      canvas: canvas,
      center: emblemCenter,
      radius: 32.0 * pinScale,
      tiltAngle: -0.45,
      rotY: -rotY * 1.25,
      color: destColor,
      isBackHalf: true,
      scale: pinScale,
    );

    // 4. Large 3D Faceted Crystal Map Pin Body (Rotating in 3D around Y-axis)
    _draw3dRotatingPinBody(
      canvas: canvas,
      center: emblemCenter,
      tipY: 38.0 * pinScale,
      topY: -32.0 * pinScale,
      equatorRadius: 26.0 * pinScale,
      crownRadius: 18.0 * pinScale,
      crownY: -16.0 * pinScale,
      rotY: rotY,
      baseColor: destColor,
      highlightColor: accentColor,
      hasReached: hasReached,
      scale: pinScale,
    );

    // 5. Front Half of Dual 3D Gyroscopic Orbital Rings (drawn in front of the pin)
    _drawOrbitalRings(
      canvas: canvas,
      center: emblemCenter,
      radius: 36.0 * pinScale,
      tiltAngle: 0.45,
      rotY: rotY,
      color: accentColor,
      isBackHalf: false,
      scale: pinScale,
    );
    _drawOrbitalRings(
      canvas: canvas,
      center: emblemCenter,
      radius: 32.0 * pinScale,
      tiltAngle: -0.45,
      rotY: -rotY * 1.25,
      color: destColor,
      isBackHalf: false,
      scale: pinScale,
    );

    // 6. Floating 3D Star / Pin Core inside the pin head
    final starScaleX = math.cos(rotY).abs().clamp(0.2, 1.0);
    canvas.save();
    canvas.translate(emblemCenter.dx, emblemCenter.dy);
    canvas.scale(starScaleX, 1.0);
    _drawStar(canvas, Offset.zero, 5, 9.0 * pinScale, 4.5 * pinScale, Colors.white);
    canvas.restore();

    // 7. Floating Holographic Destination Label Pill
    final labelY = badgeY - (42.0 * pinScale);
    final badgePrefix = hasReached ? '★ ARRIVED  ' : '★ DESTINATION  ';
    final badgePrefixColor = hasReached ? const Color(0xFF34D399) : const Color(0xFFF87171);

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: badgePrefix,
          style: TextStyle(
            color: badgePrefixColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
      style: TextStyle(
        fontSize: (12.0 * pinScale).clamp(10.0, 15.0),
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + (24.0 * pinScale);
    final pillHeight = textPainter.height + (12.0 * pinScale);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(pos.dx, labelY),
        width: pillWidth,
        height: pillHeight,
      ),
      Radius.circular(pillHeight / 2),
    );

    final pillBg = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.94)
      ..style = PaintingStyle.fill;
    final pillBorder = Paint()
      ..color = destColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.6 * pinScale
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(pillRect, pillBg);
    canvas.drawRRect(pillRect, pillBorder);
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, labelY - textPainter.height / 2),
    );
  }

  /// Draws a 3D faceted crystal pin with real Y-axis rotation and dynamic directional lighting
  void _draw3dRotatingPinBody({
    required Canvas canvas,
    required Offset center,
    required double tipY,
    required double topY,
    required double equatorRadius,
    required double crownRadius,
    required double crownY,
    required double rotY,
    required Color baseColor,
    required Color highlightColor,
    required bool hasReached,
    required double scale,
  }) {
    const int numSegments = 8;
    const double step = 2 * math.pi / numSegments;

    // Directional light vector pointing from top-left-front: (0.45, -0.65, 0.6)
    const lx = 0.45;
    const ly = -0.65;
    const lz = 0.60;

    // Equator 3D vertices
    final eqVertices = <math.Point<double>>[];
    final eqZ = <double>[];
    for (int i = 0; i < numSegments; i++) {
      final a = i * step + rotY;
      final x = equatorRadius * math.cos(a);
      final z = equatorRadius * math.sin(a);
      eqVertices.add(math.Point(x, 0.0));
      eqZ.add(z);
    }

    // Crown 3D vertices (slightly higher, offset angle)
    final crVertices = <math.Point<double>>[];
    final crZ = <double>[];
    for (int i = 0; i < numSegments; i++) {
      final a = i * step + step * 0.5 + rotY;
      final x = crownRadius * math.cos(a);
      final z = crownRadius * math.sin(a);
      crVertices.add(math.Point(x, crownY));
      crZ.add(z);
    }

    final topApex = math.Point(0.0, topY);
    final bottomTip = math.Point(0.0, tipY);

    // Halo glow around center
    final haloPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * scale);
    canvas.drawCircle(center, equatorRadius * 1.3, haloPaint);

    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1.2 * scale
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    // Helper to draw a single 3D triangle face with normal-based lighting
    void drawTriangleFace(
      math.Point<double> p1, double z1,
      math.Point<double> p2, double z2,
      math.Point<double> p3, double z3,
    ) {
      // 2D cross product for front-facing check in screen space
      final cross = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x);
      if (cross >= 0) return; // Back-facing face, cull

      // Compute 3D normal: E1 = p2 - p1, E2 = p3 - p1
      final e1x = p2.x - p1.x;
      final e1y = p2.y - p1.y;
      final e1z = z2 - z1;

      final e2x = p3.x - p1.x;
      final e2y = p3.y - p1.y;
      final e2z = z3 - z1;

      // Normal = E1 x E2
      var nx = e1y * e2z - e1z * e2y;
      var ny = e1z * e2x - e1x * e2z;
      var nz = e1x * e2y - e1y * e2x;
      final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nLen > 0.001) {
        nx /= nLen;
        ny /= nLen;
        nz /= nLen;
      }

      // Dot product with directional light
      final dot = (nx * lx + ny * ly + nz * lz).clamp(-1.0, 1.0);
      final intensity = (0.40 + 0.60 * math.max(0.0, dot)).clamp(0.25, 1.0);

      // Specular highlight boost when normal points directly at light
      final specular = math.pow(math.max(0.0, dot), 8).toDouble() * 0.45;

      final faceColor = Color.lerp(
        hasReached ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
        hasReached ? const Color(0xFF34D399) : const Color(0xFFFCA5A5),
        intensity,
      )!;

      final r = (faceColor.r * 255 + specular * 255).clamp(0, 255).toInt();
      final g = (faceColor.g * 255 + specular * 255).clamp(0, 255).toInt();
      final b = (faceColor.b * 255 + specular * 255).clamp(0, 255).toInt();
      fillPaint.color = Color.fromARGB(245, r, g, b);

      final path = Path();
      path.moveTo(center.dx + p1.x, center.dy + p1.y);
      path.lineTo(center.dx + p2.x, center.dy + p2.y);
      path.lineTo(center.dx + p3.x, center.dy + p3.y);
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, edgePaint);
    }

    // Render 3D faces:
    // 1. Bottom cone triangles (from equator down to tip)
    for (int i = 0; i < numSegments; i++) {
      final next = (i + 1) % numSegments;
      drawTriangleFace(
        bottomTip, 0.0,
        eqVertices[i], eqZ[i],
        eqVertices[next], eqZ[next],
      );
    }

    // 2. Middle belt quads (split into 2 triangles each)
    for (int i = 0; i < numSegments; i++) {
      final next = (i + 1) % numSegments;
      drawTriangleFace(
        eqVertices[i], eqZ[i],
        crVertices[i], crZ[i],
        eqVertices[next], eqZ[next],
      );
      drawTriangleFace(
        eqVertices[next], eqZ[next],
        crVertices[i], crZ[i],
        crVertices[next], crZ[next],
      );
    }

    // 3. Top crown facets (from crown to top apex)
    for (int i = 0; i < numSegments; i++) {
      final next = (i + 1) % numSegments;
      drawTriangleFace(
        topApex, 0.0,
        crVertices[next], crZ[next],
        crVertices[i], crZ[i],
      );
    }
  }

  /// Draws 3D gyroscopic orbital rings with perspective tilt, rotation, and orbiting satellite beads
  void _drawOrbitalRings({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double tiltAngle,
    required double rotY,
    required Color color,
    required bool isBackHalf,
    required double scale,
  }) {
    const int numPoints = 40;
    const double step = 2 * math.pi / numPoints;

    final ringPaint = Paint()
      ..color = color.withValues(alpha: isBackHalf ? 0.35 : 0.85)
      ..strokeWidth = (isBackHalf ? 1.2 : 2.0) * scale
      ..style = PaintingStyle.stroke;

    final cosTilt = math.cos(tiltAngle);
    final sinTilt = math.sin(tiltAngle);
    final cosRot = math.cos(rotY);
    final sinRot = math.sin(rotY);

    final path = Path();
    bool first = true;

    for (int i = 0; i <= numPoints; i++) {
      final angle = i * step;
      // 3D circle in XY plane before tilt
      final x0 = radius * math.cos(angle);
      final y0 = radius * math.sin(angle) * sinTilt;
      final z0 = radius * math.sin(angle) * cosTilt;

      // Rotate around Y-axis
      final x = x0 * cosRot + z0 * sinRot;
      final z = -x0 * sinRot + z0 * cosRot;
      final y = y0;

      // Filter by back/front half
      if ((isBackHalf && z < 0) || (!isBackHalf && z >= 0)) {
        final pt = Offset(center.dx + x, center.dy + y);
        if (first) {
          path.moveTo(pt.dx, pt.dy);
          first = false;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      } else {
        first = true;
      }
    }

    canvas.drawPath(path, ringPaint);

    // Orbiting satellite bead
    final satAngle = rotY * 1.5;
    final sx0 = radius * math.cos(satAngle);
    final sy0 = radius * math.sin(satAngle) * sinTilt;
    final sz0 = radius * math.sin(satAngle) * cosTilt;
    final sx = sx0 * cosRot + sz0 * sinRot;
    final sz = -sx0 * sinRot + sz0 * cosRot;
    final sy = sy0;

    if ((isBackHalf && sz < 0) || (!isBackHalf && sz >= 0)) {
      final satCenter = Offset(center.dx + sx, center.dy + sy);
      final beadPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final beadGlow = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale);

      canvas.drawCircle(satCenter, 3.5 * scale, beadGlow);
      canvas.drawCircle(satCenter, 2.2 * scale, beadPaint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, int points, double outerR, double innerR, Color color) {
    final path = Path();
    final step = math.pi / points;
    double angle = -math.pi / 2;

    for (int i = 0; i < 2 * points; i++) {
      final r = (i % 2 == 0) ? outerR : innerR;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      angle += step;
    }
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  /// Samples a 3D position and tangent vector along [path] at given [targetDistance] (meters).
  /// Uses a symmetric moving window to ensure smooth, continuous tangent transitions around curves.
  ({Vector3 position, Vector3 tangent}) _samplePathPositionAndTangent(
    List<SmoothedPathPoint> path,
    double targetDistance,
  ) {
    if (path.isEmpty) {
      return (position: const Vector3(0, 0, 0), tangent: const Vector3(0, 0, 1));
    }
    if (path.length == 1) {
      return (position: path.first.position, tangent: const Vector3(0, 0, 1));
    }

    Vector3 positionAt(double dist) {
      if (dist <= path.first.distanceAlongPath) return path.first.position;
      if (dist >= path.last.distanceAlongPath) return path.last.position;

      for (int i = 0; i < path.length - 1; i++) {
        final d0 = path[i].distanceAlongPath;
        final d1 = path[i + 1].distanceAlongPath;
        if (dist >= d0 && dist <= d1) {
          final span = d1 - d0;
          final u = span > 0.0001 ? ((dist - d0) / span).clamp(0.0, 1.0) : 0.0;
          final p0 = path[i].position;
          final p1 = path[i + 1].position;
          return Vector3(
            p0.x + (p1.x - p0.x) * u,
            p0.y + (p1.y - p0.y) * u,
            p0.z + (p1.z - p0.z) * u,
          );
        }
      }
      return path.last.position;
    }

    final pos = positionAt(targetDistance);

    // Symmetric moving window tangent for ultra-smooth curvature
    const window = 0.45; // 45cm lookahead/behind window
    final dBehind = math.max(path.first.distanceAlongPath, targetDistance - window);
    final dAhead = math.min(path.last.distanceAlongPath, targetDistance + window);

    final pBehind = positionAt(dBehind);
    final pAhead = positionAt(dAhead);

    final tx = pAhead.x - pBehind.x;
    final tz = pAhead.z - pBehind.z;
    final len = math.sqrt(tx * tx + tz * tz);

    Vector3 tangent;
    if (len > 0.001) {
      tangent = Vector3(tx / len, 0, tz / len);
    } else {
      tangent = const Vector3(0, 0, 1);
    }

    return (position: pos, tangent: tangent);
  }

  /// Draws a high-fidelity 3D Chevron lying flat on the floor in true perspective:
  /// - All 6 vertices are projected from ground plane coordinates
  /// - Naturally scales and tapers into the distance via camera perspective
  /// - Holographic cyan gradient fill with soft outer glow and crisp leading V
  void _draw3dFloorChevron({
    required Canvas canvas,
    required Offset pTip,
    required Offset pRightFront,
    required Offset pRightBack,
    required Offset pNotch,
    required Offset pLeftBack,
    required Offset pLeftFront,
    required double scale,
    required double brightness,
  }) {
    final chevronPath = Path()
      ..moveTo(pTip.dx, pTip.dy)
      ..lineTo(pRightFront.dx, pRightFront.dy)
      ..lineTo(pRightBack.dx, pRightBack.dy)
      ..lineTo(pNotch.dx, pNotch.dy)
      ..lineTo(pLeftBack.dx, pLeftBack.dy)
      ..lineTo(pLeftFront.dx, pLeftFront.dy)
      ..close();

    final leadingV = Path()
      ..moveTo(pLeftFront.dx, pLeftFront.dy)
      ..lineTo(pTip.dx, pTip.dy)
      ..lineTo(pRightFront.dx, pRightFront.dy);

    final bounds = chevronPath.getBounds();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.82 * brightness),
          const Color(0xFF00E5FF).withValues(alpha: 0.65 * brightness),
        ],
      ).createShader(bounds)
      ..style = PaintingStyle.fill;

    final outerHaze = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (8.0 * scale).clamp(2.0, 10.0)
      ..strokeJoin = StrokeJoin.round;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.70 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.8 * scale).clamp(0.8, 2.2)
      ..strokeJoin = StrokeJoin.round;

    final leadingVPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (3.2 * scale).clamp(1.2, 3.8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(chevronPath, outerHaze);
    canvas.drawPath(chevronPath, fillPaint);
    canvas.drawPath(chevronPath, borderPaint);
    canvas.drawPath(leadingV, leadingVPaint);
  }

  void _drawTrackingFeatureDots(
    Canvas canvas,
    List<Offset> offsets,
    double horizonY,
    double originY,
  ) {
    final rand = math.Random(101);
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < offsets.length; i += 2) {
      final pt = offsets[i];
      final depth = ((pt.dy - horizonY) / (originY - horizonY)).clamp(0.2, 1.0);

      for (int j = 0; j < 3; j++) {
        final offsetX = (rand.nextDouble() - 0.5) * 160.0 * depth;
        final offsetY = (rand.nextDouble() - 0.5) * 45.0 * depth;
        final isGold = rand.nextBool();

        dotPaint.color = (isGold ? const Color(0xFFFDE047) : Colors.white)
            .withValues(alpha: (0.35 + rand.nextDouble() * 0.45) * depth);

        final dotRadius = (1.5 + rand.nextDouble() * 2.0) * depth;
        canvas.drawCircle(Offset(pt.dx + offsetX, pt.dy + offsetY), dotRadius, dotPaint);
      }
    }
  }

  void _drawTurnMarker({
    required Canvas canvas,
    required Offset pos,
    required bool isLeft,
    required String label,
    required double distance,
    required double scale,
    bool isCurrent = false,
  }) {
    final turnColor = isCurrent ? const Color(0xFFF59E0B) : const Color(0xFF00E5FF);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    if (!isLeft) {
      canvas.scale(-1, 1);
    }

    final arrowScale = scale * 1.2;
    final stem = Path();
    stem.moveTo(0, 14 * arrowScale);
    stem.quadraticBezierTo(0, -6 * arrowScale, -20 * arrowScale, -8 * arrowScale);

    final stemGlow = Paint()
      ..color = turnColor.withValues(alpha: 0.4)
      ..strokeWidth = 8.0 * arrowScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final stemPaint = Paint()
      ..color = turnColor
      ..strokeWidth = 4.5 * arrowScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(stem, stemGlow);
    canvas.drawPath(stem, stemPaint);

    final head = Path();
    head.moveTo(-30 * arrowScale, -8 * arrowScale);
    head.lineTo(-18 * arrowScale, -18 * arrowScale);
    head.lineTo(-18 * arrowScale, 2 * arrowScale);
    head.close();

    final headGlow = Paint()
      ..color = turnColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * arrowScale;

    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(head, headGlow);
    canvas.drawPath(head, headPaint);
    canvas.restore();

    final badgeY = pos.dy - (44.0 * scale);
    final guidePaint = Paint()
      ..color = turnColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 12), guidePaint);

    final badgeWidth = 115.0 * scale;
    final badgeHeight = 28.0 * scale;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(pos.dx, badgeY),
        width: badgeWidth,
        height: badgeHeight,
      ),
      Radius.circular(14.0 * scale),
    );

    final badgeBg = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;

    final badgeBorder = Paint()
      ..color = turnColor
      ..strokeWidth = 1.5 * scale
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(badgeRect, badgeBg);
    canvas.drawRRect(badgeRect, badgeBorder);

    final textSpan = TextSpan(
      text: '$label  ${isLeft ? '←' : '→'}',
      style: TextStyle(
        color: Colors.white,
        fontSize: (11.0 * scale).clamp(9.0, 14.0),
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, badgeY - textPainter.height / 2),
    );
  }

  /// Draws a sleek, glowing AR edge indicator when the destination is outside the camera view.
  void _drawOffScreenDestCue({
    required Canvas canvas,
    required Size size,
    required double angleDelta,
    required double distance,
    required String label,
    required bool hasReached,
  }) {
    final isLeft = angleDelta < 0;
    final edgeY = size.height * 0.40;
    final destColor = hasReached ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    final textSpan = TextSpan(
      children: [
        TextSpan(text: isLeft ? '◀  ' : ''),
        TextSpan(
          text: '$label  ',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
        ),
        TextSpan(
          text: '${distance.toStringAsFixed(1)}m',
          style: TextStyle(color: destColor, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: isLeft ? '' : '  ▶'),
      ],
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + 18.0;
    final pillHeight = 28.0;
    final centerX = isLeft ? pillWidth / 2 + 12.0 : size.width - (pillWidth / 2 + 12.0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, edgeY),
        width: pillWidth,
        height: pillHeight,
      ),
      const Radius.circular(14),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.90)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = destColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );

    textPainter.paint(
      canvas,
      Offset(
        rect.center.dx - textPainter.width / 2,
        rect.center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant ArPerspectivePainter oldDelegate) => true;
}
