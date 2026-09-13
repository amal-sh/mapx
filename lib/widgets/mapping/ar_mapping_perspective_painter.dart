import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/spatial_odometry_tracker.dart';
import '../../models/edge.dart';
import '../../models/node.dart';

/// 3D AR Mapping Perspective View:
/// Renders placed spatial nodes, connected path edges, breadcrumb footsteps,
/// and an interactive floor targeting reticle in authentic 3D perspective
/// anchored to world coordinates relative to the user's camera pose.
class ArMappingPerspectivePainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final MapNode? selectedNode;
  final MapNode? linkSourceNode;
  final Position currentUserPosition;
  final double headingRadians;
  final double pitchRadians;
  final double rollRadians;
  final double cameraHeight;
  final List<BreadcrumbPoint>? breadcrumbs;
  final Position targetFloorPosition;
  final double targetDistanceAhead;
  final bool isReticleVisible;
  final double animationProgress;

  /// Internal cache of projected 2D node centers and hit radii for viewport tap selection.
  final Map<String, Rect> _projectedNodeTouchTargets = {};

  ArMappingPerspectivePainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    this.linkSourceNode,
    required this.currentUserPosition,
    required this.headingRadians,
    this.pitchRadians = -0.45,
    this.rollRadians = 0.0,
    this.cameraHeight = 1.35,
    this.breadcrumbs,
    required this.targetFloorPosition,
    required this.targetDistanceAhead,
    this.isReticleVisible = true,
    this.animationProgress = 0.0,
  });

  /// Hit-tests a screen tap against the projected 3D node badges.
  MapNode? hitTestNode(Offset tapPos, Size size, {double tolerance = 32.0}) {
    // Project and check hit targets
    for (final node in nodes.reversed) {
      final rect = _projectedNodeTouchTargets[node.id];
      if (rect != null) {
        final expanded = rect.inflate(tolerance);
        if (expanded.contains(tapPos)) {
          return node;
        }
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _projectedNodeTouchTargets.clear();

    final width = size.width;
    final height = size.height;
    final originX = width * 0.5;
    final originY = height * 0.5;

    // True physical camera focal length for portrait camera viewfinder:
    // Smartphone back cameras in portrait mode have a vertical FOV of ~60 degrees (1.047 rad).
    // Scaling focalLength to height matches the camera video stream 1:1.
    const fovV = 60.0 * math.pi / 180.0;
    final focalLength = (height * 0.5) / math.tan(fovV * 0.5);

    // Dynamic horizon line based on camera pitch
    final horizonY = originY - math.tan(pitchRadians) * focalLength;
    final groundBaselineY = height * 0.82;

    final cosH = math.cos(headingRadians);
    final sinH = math.sin(headingRadians);
    final cosP = math.cos(pitchRadians);
    final sinP = math.sin(pitchRadians);
    final cosR = math.cos(rollRadians);
    final sinR = math.sin(rollRadians);

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

    // Perspective projection from 3D world meters into 2D screen coordinates
    // Returns null if point is behind the camera (zCam <= 0.15m)
    Offset? projectWorld({
      required double x,
      required double y, // y = height above floor (0 = floor, positive = up)
      required double z,
    }) {
      final dx = x - currentUserPosition.x;
      final dy = y - cameraHeight;
      final dz = z - currentUserPosition.z;

      final zCam = dx * fx + dy * fy + dz * fz;
      if (zCam < 0.15) return null; // Behind camera or right on lens

      final xCam = dx * rx + dy * ry + dz * rz;
      final yCam = dx * ux + dy * uy + dz * uz;

      final sx = originX + (xCam / zCam) * focalLength;
      final sy = originY - (yCam / zCam) * focalLength;

      return Offset(sx, sy);
    }

    // 1. Draw 3D Connected Floor Path Ribbons (Edges)
    final nodeMap = {for (final n in nodes) n.id: n};
    final edgePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.75)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final edgeGlow = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.30)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final from = nodeMap[edge.fromNodeId];
      final to = nodeMap[edge.toNodeId];
      if (from == null || to == null) continue;

      final p1 = projectWorld(x: from.position.x, y: 0.0, z: from.position.z);
      final p2 = projectWorld(x: to.position.x, y: 0.0, z: to.position.z);
      if (p1 == null || p2 == null) continue;

      // Depth based thickness
      final avgY = (p1.dy + p2.dy) * 0.5;
      final depthRatio = ((avgY - horizonY) / (groundBaselineY - horizonY)).clamp(0.2, 1.2);

      edgeGlow.strokeWidth = 9.0 * depthRatio;
      edgePaint.strokeWidth = 3.0 * depthRatio;

      canvas.drawLine(p1, p2, edgeGlow);
      canvas.drawLine(p1, p2, edgePaint);

      // Edge distance pill midway
      final midX = (p1.dx + p2.dx) * 0.5;
      final midY = (p1.dy + p2.dy) * 0.5;
      if (depthRatio > 0.35) {
        _drawEdgeDistanceBadge(
          canvas: canvas,
          pos: Offset(midX, midY),
          distance: edge.weight,
          scale: depthRatio,
        );
      }
    }

    // 2. Draw 3D Breadcrumb Footsteps on Floor (Dropped dots along walked path)
    if (breadcrumbs != null && breadcrumbs!.isNotEmpty) {
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
      for (int i = 0; i < breadcrumbs!.length; i++) {
        final b = breadcrumbs![i];
        final p = projectWorld(x: b.position.x, y: 0.0, z: b.position.z);
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
        if (i == breadcrumbs!.length - 1) {
          final pulseR = (baseR * 1.8) + (6.0 * depthRatio * animationProgress);
          final pulsePaint = Paint()
            ..color = const Color(0xFF00E5FF).withValues(alpha: (0.6 * (1.0 - animationProgress)).clamp(0.0, 0.6))
            ..strokeWidth = 1.5 * depthRatio
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(p, pulseR, pulsePaint);
        }
      }
    }

    // 3. Draw 3D Interactive Floor Targeting Reticle
    if (isReticleVisible) {
      _drawFloorReticle(
        canvas: canvas,
        projectWorld: projectWorld,
        target: targetFloorPosition,
        distanceAhead: targetDistanceAhead,
        horizonY: horizonY,
        originY: groundBaselineY,
        animationProgress: animationProgress,
      );
    }

    // 4. Draw 3D Spatial Placed Nodes (Floor ripple + Vertical laser + Floating Badge)
    // Sort nodes by camera depth (zCam descending) so far nodes render behind closer nodes
    final sortedNodes = List<MapNode>.from(nodes);
    sortedNodes.sort((a, b) {
      final da = (a.position.x - currentUserPosition.x) * fx + (a.position.z - currentUserPosition.z) * fz;
      final db = (b.position.x - currentUserPosition.x) * fx + (b.position.z - currentUserPosition.z) * fz;
      return db.compareTo(da);
    });

    for (final node in sortedNodes) {
      final isSelected = selectedNode?.id == node.id;
      final isLinkSource = linkSourceNode?.id == node.id;

      _drawSpatialNodeBeacon(
        canvas: canvas,
        size: size,
        projectWorld: projectWorld,
        node: node,
        isSelected: isSelected,
        isLinkSource: isLinkSource,
        horizonY: horizonY,
        originY: groundBaselineY,
        animationProgress: animationProgress,
      );
    }
  }

  /// Draws the 3D Floor Reticle projected in world perspective.
  void _drawFloorReticle({
    required Canvas canvas,
    required Offset? Function({required double x, required double y, required double z}) projectWorld,
    required Position target,
    required double distanceAhead,
    required double horizonY,
    required double originY,
    required double animationProgress,
  }) {
    final floorPos = projectWorld(x: target.x, y: 0.0, z: target.z);
    if (floorPos == null) return;

    final depthRatio = ((floorPos.dy - horizonY) / (originY - horizonY)).clamp(0.25, 1.25);
    final s = depthRatio;

    const reticleColor = Color(0xFF38BDF8);

    // 1. Concentric floor ring in 3D ground perspective
    // Sample 16 points around the floor circle
    const radiusMeters = 0.45;
    final ringPoints = <Offset>[];
    for (int i = 0; i <= 16; i++) {
      final angle = (i / 16.0) * math.pi * 2;
      final rx = target.x + math.cos(angle) * radiusMeters;
      final rz = target.z + math.sin(angle) * radiusMeters;
      final p = projectWorld(x: rx, y: 0.0, z: rz);
      if (p != null) ringPoints.add(p);
    }

    if (ringPoints.length > 2) {
      final path = Path()..moveTo(ringPoints.first.dx, ringPoints.first.dy);
      for (int i = 1; i < ringPoints.length; i++) {
        path.lineTo(ringPoints[i].dx, ringPoints[i].dy);
      }
      path.close();

      // Floor fill
      final fillPaint = Paint()
        ..color = reticleColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Floor border
      final strokePaint = Paint()
        ..color = reticleColor.withValues(alpha: 0.85)
        ..strokeWidth = 2.0 * s
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, strokePaint);
    }

    // 2. Animated pulsing ripple ring expanding outwards
    final rippleRadius = radiusMeters * (0.5 + 0.9 * animationProgress);
    final ripplePoints = <Offset>[];
    for (int i = 0; i <= 16; i++) {
      final angle = (i / 16.0) * math.pi * 2;
      final rx = target.x + math.cos(angle) * rippleRadius;
      final rz = target.z + math.sin(angle) * rippleRadius;
      final p = projectWorld(x: rx, y: 0.0, z: rz);
      if (p != null) ripplePoints.add(p);
    }
    if (ripplePoints.length > 2) {
      final ripplePath = Path()..moveTo(ripplePoints.first.dx, ripplePoints.first.dy);
      for (int i = 1; i < ripplePoints.length; i++) {
        ripplePath.lineTo(ripplePoints[i].dx, ripplePoints[i].dy);
      }
      ripplePath.close();

      final ripplePaint = Paint()
        ..color = reticleColor.withValues(alpha: (0.6 * (1.0 - animationProgress)).clamp(0.0, 0.6))
        ..strokeWidth = 1.5 * s
        ..style = PaintingStyle.stroke;
      canvas.drawPath(ripplePath, ripplePaint);
    }

    // 3. Center Crosshair Dot on Floor
    final centerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(floorPos, 3.5 * s, centerDot);

    // 4. Holographic vertical guideline
    final guidelineTop = Offset(floorPos.dx, floorPos.dy - (42.0 * s));
    final guidePaint = Paint()
      ..color = reticleColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.4 * s;
    canvas.drawLine(floorPos, guidelineTop, guidePaint);

    // 5. Floating Reticle Badge
    final badgeCenter = guidelineTop;
    final textSpan = TextSpan(
      children: [
        const TextSpan(
          text: 'TARGET  ',
          style: TextStyle(
            color: Color(0xFF38BDF8),
            fontWeight: FontWeight.w900,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        TextSpan(
          text: '${distanceAhead.toStringAsFixed(1)}m',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ],
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + 16 * s;
    final pillHeight = textPainter.height + 8 * s;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: badgeCenter, width: pillWidth, height: pillHeight),
      Radius.circular(pillHeight / 2),
    );

    final badgeBg = Paint()
      ..color = const Color(0xFF090D16).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;
    final badgeBorder = Paint()
      ..color = reticleColor.withValues(alpha: 0.8)
      ..strokeWidth = 1.2 * s
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(pillRect, badgeBg);
    canvas.drawRRect(pillRect, badgeBorder);
    textPainter.paint(
      canvas,
      Offset(badgeCenter.dx - textPainter.width / 2, badgeCenter.dy - textPainter.height / 2),
    );
  }

  /// Draws an authentic 3D spatial node beacon:
  /// - Floor ripple ring anchored at (x, 0, z)
  /// - Vertical laser light beam rising from floor
  /// - Floating 3D badge with icon, label, and distance
  void _drawSpatialNodeBeacon({
    required Canvas canvas,
    required Size size,
    required Offset? Function({required double x, required double y, required double z}) projectWorld,
    required MapNode node,
    required bool isSelected,
    required bool isLinkSource,
    required double horizonY,
    required double originY,
    required double animationProgress,
  }) {
    // Color based on node type and selection
    Color baseColor;
    if (isSelected || isLinkSource) {
      baseColor = const Color(0xFFF59E0B); // Amber / Gold
    } else {
      switch (node.type) {
        case NodeType.room:
          baseColor = const Color(0xFF2563EB); // Vibrant Blue
          break;
        case NodeType.junction:
          baseColor = const Color(0xFF10B981); // Emerald Green
          break;
        case NodeType.stair:
          baseColor = const Color(0xFFF97316); // Orange
          break;
        case NodeType.elevator:
          baseColor = const Color(0xFF8B5CF6); // Purple
          break;
        case NodeType.doorway:
          baseColor = const Color(0xFF06B6D4); // Cyan
          break;
      }
    }

    final floorPos = projectWorld(x: node.position.x, y: 0.0, z: node.position.z);
    if (floorPos == null || floorPos.dx < -60 || floorPos.dx > size.width + 60) {
      // Node is off-screen or behind camera: draw directional off-screen indicator if nearby
      final dx = node.position.x - currentUserPosition.x;
      final dz = node.position.z - currentUserPosition.z;
      final nodeDist = math.sqrt(dx * dx + dz * dz);
      if (nodeDist > 0.3 && nodeDist < 20.0) {
        final nodeBearing = math.atan2(dx, dz);
        var relAngle = nodeBearing - headingRadians;
        while (relAngle < -math.pi) {
          relAngle += 2 * math.pi;
        }
        while (relAngle > math.pi) {
          relAngle -= 2 * math.pi;
        }
        _drawOffScreenNodeIndicator(
          canvas: canvas,
          size: size,
          node: node,
          angleDelta: relAngle,
          distance: nodeDist,
          color: baseColor,
        );
      }
      if (floorPos == null) return;
    }

    final depthRatio = ((floorPos.dy - horizonY) / (originY - horizonY)).clamp(0.20, 1.35);
    final s = depthRatio;

    // 1. Concentric Floor Anchor Rings in 3D Perspective
    const floorRadius = 0.32;
    final floorRingPoints = <Offset>[];
    for (int i = 0; i <= 16; i++) {
      final angle = (i / 16.0) * math.pi * 2;
      final rx = node.position.x + math.cos(angle) * floorRadius;
      final rz = node.position.z + math.sin(angle) * floorRadius;
      final p = projectWorld(x: rx, y: 0.0, z: rz);
      if (p != null) floorRingPoints.add(p);
    }
    if (floorRingPoints.length > 2) {
      final ringPath = Path()..moveTo(floorRingPoints.first.dx, floorRingPoints.first.dy);
      for (int i = 1; i < floorRingPoints.length; i++) {
        ringPath.lineTo(floorRingPoints[i].dx, floorRingPoints[i].dy);
      }
      ringPath.close();

      final floorFill = Paint()
        ..color = baseColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;
      final floorBorder = Paint()
        ..color = baseColor.withValues(alpha: 0.85)
        ..strokeWidth = 2.0 * s
        ..style = PaintingStyle.stroke;

      canvas.drawPath(ringPath, floorFill);
      canvas.drawPath(ringPath, floorBorder);
    }

    // Floor center anchor dot
    canvas.drawCircle(
      floorPos,
      4.0 * s,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // 2. Vertical Holographic Laser Light Pillar (Height: 0.9m above floor)
    final badgePos = projectWorld(x: node.position.x, y: 0.9, z: node.position.z) ??
        Offset(floorPos.dx, floorPos.dy - 64.0 * s);

    // Laser beam core & glow
    final beamGlow = Paint()
      ..color = baseColor.withValues(alpha: 0.35)
      ..strokeWidth = 5.0 * s;
    final beamCore = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.6 * s;

    canvas.drawLine(floorPos, badgePos, beamGlow);
    canvas.drawLine(floorPos, badgePos, beamCore);

    // 3. Floating 3D Node Emblem & Icon
    final emblemRadius = (16.0 * s).clamp(11.0, 26.0);
    final emblemCenter = badgePos;

    // Outer glow halo
    if (isSelected || isLinkSource) {
      final pulseHalo = Paint()
        ..color = baseColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(emblemCenter, emblemRadius + 6.0 * s, pulseHalo);
    }

    // Emblem body
    final emblemBg = Paint()
      ..color = const Color(0xFF0B111E).withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    final emblemBorder = Paint()
      ..color = isSelected ? Colors.white : baseColor
      ..strokeWidth = (isSelected ? 2.8 : 2.0) * s
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(emblemCenter, emblemRadius, emblemBg);
    canvas.drawCircle(emblemCenter, emblemRadius, emblemBorder);

    // Draw Vector Icon inside Emblem
    _drawNodeVectorIcon(
      canvas: canvas,
      center: emblemCenter,
      type: node.type,
      color: isSelected ? baseColor : Colors.white,
      radius: emblemRadius * 0.55,
    );

    // 4. Floating Name Tag Pill (Above Emblem)
    final distanceMeters = currentUserPosition.distanceTo(node.position);
    final labelPos = Offset(emblemCenter.dx, emblemCenter.dy - emblemRadius - 12.0 * s);

    final labelSpan = TextSpan(
      children: [
        TextSpan(
          text: node.label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: (11.0 * s).clamp(9.0, 14.0),
          ),
        ),
        TextSpan(
          text: ' • ${distanceMeters.toStringAsFixed(1)}m',
          style: TextStyle(
            color: baseColor.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
            fontSize: (10.0 * s).clamp(8.0, 12.0),
          ),
        ),
      ],
    );

    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final tagWidth = labelPainter.width + 16.0 * s;
    final tagHeight = labelPainter.height + 8.0 * s;
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: labelPos, width: tagWidth, height: tagHeight),
      Radius.circular(tagHeight / 2),
    );

    final tagBg = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final tagBorder = Paint()
      ..color = (isSelected ? const Color(0xFFF59E0B) : baseColor).withValues(alpha: 0.8)
      ..strokeWidth = (isSelected ? 1.8 : 1.2) * s
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(tagRect, tagBg);
    canvas.drawRRect(tagRect, tagBorder);
    labelPainter.paint(
      canvas,
      Offset(labelPos.dx - labelPainter.width / 2, labelPos.dy - labelPainter.height / 2),
    );

    // Save touch target bounding rect for viewport tap hit-testing across the entire 3D beacon
    final topY = math.min(badgePos.dy, floorPos.dy) - tagHeight - 8.0 * s;
    final bottomY = math.max(badgePos.dy, floorPos.dy) + 16.0 * s;
    final beaconCenter = Offset(emblemCenter.dx, (topY + bottomY) * 0.5);
    final beaconHeight = (bottomY - topY).abs();

    if (beaconCenter.dx >= -40 &&
        beaconCenter.dx <= size.width + 40 &&
        beaconCenter.dy >= -40 &&
        beaconCenter.dy <= size.height + 40) {
      final totalTargetRect = Rect.fromCenter(
        center: beaconCenter,
        width: math.max(tagWidth, emblemRadius * 3.0),
        height: math.max(beaconHeight, emblemRadius * 2 + tagHeight + 16.0 * s),
      );
      _projectedNodeTouchTargets[node.id] = totalTargetRect;
    }
  }

  /// Draws vector icon representing the NodeType.
  void _drawNodeVectorIcon({
    required Canvas canvas,
    required Offset center,
    required NodeType type,
    required Color color,
    required double radius,
  }) {
    final iconPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (type) {
      case NodeType.junction:
        // Waypoint crosshair / diamond
        final path = Path();
        path.moveTo(center.dx, center.dy - radius);
        path.lineTo(center.dx + radius, center.dy);
        path.lineTo(center.dx, center.dy + radius);
        path.lineTo(center.dx - radius, center.dy);
        path.close();
        canvas.drawPath(path, fillPaint);
        break;

      case NodeType.room:
        // Door / Building square
        final rect = Rect.fromCenter(center: center, width: radius * 1.5, height: radius * 1.6);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), iconPaint);
        canvas.drawCircle(Offset(center.dx + radius * 0.35, center.dy), 1.5, fillPaint);
        break;

      case NodeType.stair:
        // Stepped path
        final path = Path();
        path.moveTo(center.dx - radius, center.dy + radius);
        path.lineTo(center.dx - radius * 0.3, center.dy + radius);
        path.lineTo(center.dx - radius * 0.3, center.dy);
        path.lineTo(center.dx + radius * 0.4, center.dy);
        path.lineTo(center.dx + radius * 0.4, center.dy - radius);
        path.lineTo(center.dx + radius, center.dy - radius);
        canvas.drawPath(path, iconPaint);
        break;

      case NodeType.elevator:
        // Elevator box with up/down arrows
        final rect = Rect.fromCenter(center: center, width: radius * 1.6, height: radius * 1.6);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), iconPaint);
        // Up arrow
        final upPath = Path()
          ..moveTo(center.dx, center.dy - radius * 0.5)
          ..lineTo(center.dx - radius * 0.3, center.dy - radius * 0.1)
          ..lineTo(center.dx + radius * 0.3, center.dy - radius * 0.1)
          ..close();
        // Down arrow
        final downPath = Path()
          ..moveTo(center.dx, center.dy + radius * 0.5)
          ..lineTo(center.dx - radius * 0.3, center.dy + radius * 0.1)
          ..lineTo(center.dx + radius * 0.3, center.dy + radius * 0.1)
          ..close();
        canvas.drawPath(upPath, fillPaint);
        canvas.drawPath(downPath, fillPaint);
        break;

      case NodeType.doorway:
        canvas.drawCircle(center, radius * 0.65, fillPaint);
        break;
    }
  }

  /// Draws edge distance pill along 3D path line.
  void _drawEdgeDistanceBadge({
    required Canvas canvas,
    required Offset pos,
    required double distance,
    required double scale,
  }) {
    final textSpan = TextSpan(
      text: '${distance.toStringAsFixed(1)}m',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: (9.0 * scale).clamp(8.0, 11.0),
      ),
    );

    final painter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = painter.width + 10.0 * scale;
    final pillHeight = painter.height + 6.0 * scale;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: pillWidth, height: pillHeight),
      Radius.circular(pillHeight / 2),
    );

    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.88)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.6)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    painter.paint(canvas, Offset(pos.dx - painter.width / 2, pos.dy - painter.height / 2));
  }

  /// Draws a directional edge indicator when a node is outside the camera field of view.
  void _drawOffScreenNodeIndicator({
    required Canvas canvas,
    required Size size,
    required MapNode node,
    required double angleDelta,
    required double distance,
    required Color color,
  }) {
    final isLeft = angleDelta < 0;
    final edgeY = size.height * 0.42;

    final textSpan = TextSpan(
      children: [
        TextSpan(text: isLeft ? '◀ ' : ''),
        TextSpan(
          text: '${node.label} ',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
        ),
        TextSpan(
          text: '${distance.toStringAsFixed(1)}m',
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        TextSpan(text: isLeft ? '' : ' ▶'),
      ],
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillWidth = textPainter.width + 16.0;
    final pillHeight = 24.0;
    final centerX = isLeft ? pillWidth / 2 + 12.0 : size.width - (pillWidth / 2 + 12.0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, edgeY),
        width: pillWidth,
        height: pillHeight,
      ),
      const Radius.circular(12),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.65)
        ..strokeWidth = 1.2
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
  bool shouldRepaint(covariant ArMappingPerspectivePainter oldDelegate) => true;
}
