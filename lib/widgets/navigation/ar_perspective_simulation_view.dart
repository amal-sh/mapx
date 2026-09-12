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
  final bool isOverlay;

  const ArPerspectiveSimulationView({
    super.key,
    required this.smoothedPoints,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    required this.destination,
    this.startNode,
    required this.animationProgress,
    this.userPosition,
    this.isOverlay = false,
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
          isOverlay: isOverlay,
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
  final bool isOverlay;

  ArPerspectivePainter({
    required this.points,
    required this.turnInstructions,
    required this.activeStep,
    required this.animationProgress,
    required this.destination,
    this.startNode,
    this.userPosition,
    this.isOverlay = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Horizon line for 3D corridor perspective
    final horizonY = height * 0.35;
    final originX = width * 0.5;
    final originY = height * 0.82;

    // 1. Draw floor grid when in standalone simulation mode
    if (!isOverlay) {
      final floorGradient = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B14), Color(0xFF0F172A)],
        ).createShader(Rect.fromLTWH(0, horizonY, width, height - horizonY));
      canvas.drawRect(Rect.fromLTWH(0, horizonY, width, height - horizonY), floorGradient);

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

    // Determine forward heading vector F
    double fx = 0.0;
    double fz = 1.0;
    if (points.isNotEmpty && startIdx < points.length - 1) {
      final lookAhead = math.min(startIdx + 4, points.length - 1);
      final pNext = points[lookAhead].position;
      final dx = pNext.x - points[startIdx].position.x;
      final dz = pNext.z - points[startIdx].position.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len > 0.001) {
        fx = dx / len;
        fz = dz / len;
      }
    }
    // Right vector R (perpendicular to F, pointing right)
    final rx = fz;
    final rz = -fx;

    // Perspective projection function from 3D world meters into 2D screen coordinates
    // Returns null if point is behind the camera viewpoint (zCam < -0.35m)
    Offset? project(Vector3 pos) {
      final dx = pos.x - anchorPos.x;
      final dz = pos.z - anchorPos.z;

      final zCam = dx * fx + dz * fz;
      final xCam = dx * rx + dz * rz;

      if (zCam < -0.35) return null;

      final s = 4.5 / (4.5 + math.max(0.0, zCam));
      final sy = horizonY + (originY - horizonY) * s;
      final lateralScale = width * 0.22;
      final sx = originX + (xCam * lateralScale) * s;

      return Offset(sx.clamp(-120.0, width + 120.0), sy);
    }

    final visiblePoints = points.isNotEmpty ? points.sublist(startIdx) : <SmoothedPathPoint>[];
    final screenOffsets = <Offset>[];
    for (final pt in visiblePoints) {
      final proj = project(pt.position);
      if (proj != null) screenOffsets.add(proj);
    }

    // 3. Draw smoothed path glow line
    if (screenOffsets.length >= 2) {
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.28)
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final linePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(screenOffsets.first.dx, screenOffsets.first.dy);
      for (int i = 1; i < screenOffsets.length; i++) {
        path.lineTo(screenOffsets[i].dx, screenOffsets[i].dy);
      }

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, linePaint);

      // Draw subtle AR feature/tracking sparkle points like in real ARCore
      _drawTrackingFeatureDots(canvas, screenOffsets, horizonY, originY);
    }

    // 4. Draw large corridor-spanning directional chevrons matching real AR navigation
    if (screenOffsets.length >= 2) {
      final numChevrons = math.min(7, math.max(4, (screenOffsets.length / 3).round()));
      for (int c = 0; c < numChevrons; c++) {
        final ratio = ((c + 0.15) / numChevrons).clamp(0.0, 0.95);
        final idx = (ratio * (screenOffsets.length - 1)).round().clamp(0, screenOffsets.length - 2);

        final current = screenOffsets[idx];
        final next = screenOffsets[idx + 1];

        final dx = next.dx - current.dx;
        final dy = next.dy - current.dy;
        final angle = math.atan2(dy, dx);

        final depthRatio = ((current.dy - horizonY) / (originY - horizonY)).clamp(0.18, 1.0);
        final scale = 0.38 + 0.62 * depthRatio;

        final pulsePhase = (ratio - animationProgress) % 1.0;
        final brightness = (0.75 + 0.25 * math.sin((pulsePhase + 1.0) % 1.0 * math.pi)).clamp(0.55, 1.0);

        _drawChevron(canvas, current, angle, scale, brightness, width);
      }

      // Draw AR floor plane tracking ring in the foreground
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
    if (destPos != null && destPos.dy >= horizonY - 40 && destPos.dy <= height + 60) {
      final depthRatio = ((destPos.dy - horizonY) / (originY - horizonY)).clamp(0.25, 1.25);
      _drawDestinationMarker(
        canvas: canvas,
        pos: destPos,
        label: destination.label,
        scale: depthRatio,
      );
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

  /// Draws a high-fidelity 3D Destination Marker in AR:
  /// - Ruby red pulsating concentric bullseye rings on floor
  /// - Holographic vertical laser light column
  /// - Floating 3D Map Pin shape with inner white 5-pointed star icon
  /// - Floating luminous "★ DESTINATION • [Label]" badge
  void _drawDestinationMarker({
    required Canvas canvas,
    required Offset pos,
    required String label,
    required double scale,
  }) {
    const destColor = Color(0xFFEF4444); // Crimson ruby red

    // 1. Concentric pulsing bullseye rings on floor
    final pulseRing = Paint()
      ..color = destColor.withValues(alpha: (0.55 * (1.0 - animationProgress)).clamp(0.0, 0.55))
      ..strokeWidth = 3.0 * scale
      ..style = PaintingStyle.stroke;

    final midRing = Paint()
      ..color = destColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;

    final innerFill = Paint()
      ..color = destColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final pulseRadius = (20.0 + 14.0 * (1.0 - animationProgress)) * scale;
    canvas.drawCircle(pos, pulseRadius, pulseRing);
    canvas.drawCircle(pos, 16.0 * scale, midRing);
    canvas.drawCircle(pos, 9.0 * scale, innerFill);
    canvas.drawCircle(pos, 3.5 * scale, Paint()..color = Colors.white..style = PaintingStyle.fill);

    // 2. Holographic vertical laser light beam from floor to floating pin
    final badgeY = pos.dy - (68.0 * scale);
    final beamGlow = Paint()
      ..color = destColor.withValues(alpha: 0.35)
      ..strokeWidth = 7.0 * scale;
    final beamCore = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.0 * scale;
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 22 * scale), beamGlow);
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 22 * scale), beamCore);

    // 3. Floating 3D Destination Map Pin Silhouette
    final pinHeadCenter = Offset(pos.dx, badgeY);
    final pinRadius = 18.0 * scale;
    final pinTip = Offset(pos.dx, badgeY + 22.0 * scale);

    // Map Pin Path
    final pinPath = Path();
    pinPath.moveTo(pinTip.dx, pinTip.dy);
    pinPath.quadraticBezierTo(
      pinHeadCenter.dx - pinRadius * 1.1,
      pinHeadCenter.dy + pinRadius * 0.4,
      pinHeadCenter.dx - pinRadius,
      pinHeadCenter.dy,
    );
    pinPath.arcTo(
      Rect.fromCircle(center: pinHeadCenter, radius: pinRadius),
      math.pi,
      math.pi,
      false,
    );
    pinPath.quadraticBezierTo(
      pinHeadCenter.dx + pinRadius * 1.1,
      pinHeadCenter.dy + pinRadius * 0.4,
      pinTip.dx,
      pinTip.dy,
    );
    pinPath.close();

    // Outer glow
    final pinGlow = Paint()
      ..color = destColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(pinPath, pinGlow);

    // Pin body gradient
    final pinFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFF87171),
          const Color(0xFFDC2626),
          const Color(0xFF991B1B),
        ],
      ).createShader(Rect.fromCircle(center: pinHeadCenter, radius: pinRadius * 1.4))
      ..style = PaintingStyle.fill;
    canvas.drawPath(pinPath, pinFill);

    final pinBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawPath(pinPath, pinBorder);

    // Crisp Vector Star / Flag Icon inside Pin Head
    _drawStar(canvas, pinHeadCenter, 5, 8.0 * scale, 4.0 * scale, Colors.white);

    // 4. Floating Destination Label Pill
    final labelY = badgeY - (28.0 * scale);
    final textSpan = TextSpan(
      children: [
        const TextSpan(
          text: '★ DESTINATION  ',
          style: TextStyle(
            color: Color(0xFFF87171),
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
      ..color = destColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.4 * scale
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(pillRect, pillBg);
    canvas.drawRRect(pillRect, pillBorder);
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, labelY - textPainter.height / 2),
    );
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

  void _drawChevron(
    Canvas canvas,
    Offset pos,
    double angle,
    double scale,
    double brightness,
    double screenWidth,
  ) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    final w = math.min(screenWidth * 0.78, 290.0) * scale;
    final lTip = 68.0 * scale;
    final lBand = 48.0 * scale;

    final path = Path();
    path.moveTo(lTip, 0);
    path.lineTo(0, -w * 0.5);
    path.lineTo(-lBand, -w * 0.5);
    path.lineTo(lTip - lBand, 0);
    path.lineTo(-lBand, w * 0.5);
    path.lineTo(0, w * 0.5);
    path.close();

    final outerHaze = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.40 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0 * scale
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF00F5FF).withValues(alpha: 0.78 * brightness),
          const Color(0xFF38BDF8).withValues(alpha: 0.88 * brightness),
          const Color(0xFF00F5FF).withValues(alpha: 0.78 * brightness),
        ],
      ).createShader(Rect.fromLTWH(-lBand, -w * 0.5, lTip + lBand, w))
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeJoin = StrokeJoin.round;

    final leadingV = Path();
    leadingV.moveTo(0, -w * 0.5);
    leadingV.lineTo(lTip, 0);
    leadingV.lineTo(0, w * 0.5);

    final leadingVPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, outerHaze);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
    canvas.drawPath(leadingV, leadingVPaint);

    canvas.restore();
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

  @override
  bool shouldRepaint(covariant ArPerspectivePainter oldDelegate) => true;
}
