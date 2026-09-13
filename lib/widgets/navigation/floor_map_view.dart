import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/bezier_smoother.dart';
import '../../models/edge.dart';
import '../../models/node.dart';
import '../../native/ar_bridge.dart';

/// Fullscreen 2D Floor Map View providing a clear overview with route & turn arrows.
class FloorMapView extends StatelessWidget {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final List<MapNode> path;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final MapNode destination;
  final MapNode? startNode;
  final Vector3? userPosition;
  final List<Position>? walkedBreadcrumbs;

  const FloorMapView({
    super.key,
    required this.nodes,
    required this.edges,
    required this.path,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    required this.destination,
    this.startNode,
    this.userPosition,
    this.walkedBreadcrumbs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B14),
      child: CustomPaint(
        painter: FloorMapPainter(
          nodes: nodes,
          edges: edges,
          path: path,
          turnInstructions: turnInstructions,
          currentInstructionIndex: currentInstructionIndex,
          destination: destination,
          startNode: startNode,
          userPosition: userPosition,
          walkedBreadcrumbs: walkedBreadcrumbs,
          isMiniMap: false,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Canvas painter for 2D floor maps (both Mini-Map radar and Fullscreen 2D View).
/// Automatically normalizes coordinates and renders directional arrows along each route segment,
/// clearly indicating Start (Green 'A') and Destination (Red 'B').
class FloorMapPainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final List<MapNode> path;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final MapNode? destination;
  final MapNode? startNode;
  final Vector3? userPosition;
  final List<Position>? walkedBreadcrumbs;
  final bool isMiniMap;

  FloorMapPainter({
    required this.nodes,
    required this.edges,
    required this.path,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    this.destination,
    this.startNode,
    this.userPosition,
    this.walkedBreadcrumbs,
    required this.isMiniMap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final pad = isMiniMap ? 14.0 : 40.0;
    double minX = nodes.first.position.x;
    double maxX = nodes.first.position.x;
    double minZ = nodes.first.position.z;
    double maxZ = nodes.first.position.z;

    for (final n in nodes) {
      if (n.position.x < minX) minX = n.position.x;
      if (n.position.x > maxX) maxX = n.position.x;
      if (n.position.z < minZ) minZ = n.position.z;
      if (n.position.z > maxZ) maxZ = n.position.z;
    }

    final spanX = math.max(1.0, maxX - minX);
    final spanZ = math.max(1.0, maxZ - minZ);

    final availableW = size.width - (pad * 2);
    final availableH = size.height - (pad * 2);

    final scale = math.min(availableW / spanX, availableH / spanZ);
    final offsetX = pad + (availableW - spanX * scale) / 2 - minX * scale;
    final offsetY = pad + (availableH - spanZ * scale) / 2 - minZ * scale;

    Offset mapPoint(Position pos) =>
        Offset(offsetX + pos.x * scale, offsetY + pos.z * scale);

    final nodeMap = {for (final n in nodes) n.id: n};

    // 1. Draw floor edges (subtle)
    final edgePaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.6)
      ..strokeWidth = isMiniMap ? 1.0 : 2.0
      ..style = PaintingStyle.stroke;

    for (final e in edges) {
      final from = nodeMap[e.fromNodeId];
      final to = nodeMap[e.toNodeId];
      if (from == null || to == null) continue;
      canvas.drawLine(mapPoint(from.position), mapPoint(to.position), edgePaint);
    }

    // 2. Draw active route glow ribbon
    if (path.length >= 2) {
      final routeGlow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.3)
        ..strokeWidth = isMiniMap ? 6.0 : 10.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final routePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = isMiniMap ? 2.5 : 4.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final routePath = Path();
      routePath.moveTo(mapPoint(path.first.position).dx, mapPoint(path.first.position).dy);
      for (int i = 1; i < path.length; i++) {
        final p = mapPoint(path[i].position);
        routePath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(routePath, routeGlow);
      canvas.drawPath(routePath, routePaint);

      // 3. Draw directional arrows along each path segment
      final arrowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      for (int i = 0; i < path.length - 1; i++) {
        final p1 = mapPoint(path[i].position);
        final p2 = mapPoint(path[i + 1].position);

        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);

        canvas.save();
        canvas.translate(mid.dx, mid.dy);
        canvas.rotate(angle);

        final arrSize = isMiniMap ? 4.0 : 7.0;
        final arrow = Path();
        arrow.moveTo(arrSize * 1.2, 0);
        arrow.lineTo(-arrSize, -arrSize);
        arrow.lineTo(-arrSize * 0.4, 0);
        arrow.lineTo(-arrSize, arrSize);
        arrow.close();

        canvas.drawPath(arrow, arrowPaint);
        canvas.restore();
      }
    }

    // 4. Draw Turn instruction badges at corner junctions
    for (int i = 1; i < turnInstructions.length - 1; i++) {
      final inst = turnInstructions[i];
      final pos = Offset(
        offsetX + inst.position.x * scale,
        offsetY + inst.position.z * scale,
      );

      final lower = inst.instruction.toLowerCase();
      final isLeft = lower.contains('left');
      final isRight = lower.contains('right');

      if (isLeft || isRight) {
        final turnPaint = Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(pos, isMiniMap ? 4.0 : 7.0, turnPaint);

        if (!isMiniMap) {
          final turnText = TextSpan(
            text: isLeft ? '↰' : '↱',
            style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
          );
          final tp = TextPainter(text: turnText, textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
        }
      }
    }

    // 5. Draw Start Point (Green 'A')
    if (path.isNotEmpty) {
      final startPos = mapPoint(path.first.position);
      final startRipple = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(startPos, isMiniMap ? 7.0 : 12.0, startRipple);

      final startDot = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(startPos, isMiniMap ? 4.0 : 7.0, startDot);

      if (!isMiniMap) {
        final startText = TextSpan(
          text: 'A',
          style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900),
        );
        final tp = TextPainter(text: startText, textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(startPos.dx - tp.width / 2, startPos.dy - tp.height / 2));
      }

      // Destination Point (Red 'B')
      final destPos = mapPoint(path.last.position);
      final destRipple = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(destPos, isMiniMap ? 7.0 : 12.0, destRipple);

      final destPaint = Paint()
        ..color = const Color(0xFFEF4444)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(destPos, isMiniMap ? 4.0 : 7.0, destPaint);

      if (!isMiniMap) {
        final destText = TextSpan(
          text: 'B',
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
        );
        final tp = TextPainter(text: destText, textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(destPos.dx - tp.width / 2, destPos.dy - tp.height / 2));
      }

      // 5.5 Draw walked breadcrumbs (Dropped dots along tracked walking path)
      if (walkedBreadcrumbs != null && walkedBreadcrumbs!.isNotEmpty) {
        final breadcrumbTrailPaint = Paint()
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.45)
          ..strokeWidth = isMiniMap ? 1.5 : 2.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        final breadcrumbDotPaint = Paint()
          ..color = const Color(0xFF38BDF8)
          ..style = PaintingStyle.fill;

        Offset? prevPoint;
        for (final b in walkedBreadcrumbs!) {
          final pt = mapPoint(b);
          if (prevPoint != null) {
            canvas.drawLine(prevPoint, pt, breadcrumbTrailPaint);
          }
          prevPoint = pt;
          canvas.drawCircle(pt, isMiniMap ? 2.0 : 3.5, breadcrumbDotPaint);
        }
      }

      // User's active position dot if simulated walk is happening
      if (userPosition != null) {
        final userPos = mapPoint(Position(x: userPosition!.x, y: userPosition!.y, z: userPosition!.z));
        final userPaint = Paint()
          ..color = const Color(0xFF00E5FF)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(userPos, isMiniMap ? 5.0 : 8.0, userPaint);
      }

      if (!isMiniMap) {
        // Node labels
        for (final n in nodes) {
          final p = mapPoint(n.position);
          final isStartOrDest = n.id == path.first.id || n.id == path.last.id;
          final textSpan = TextSpan(
            text: n.label,
            style: TextStyle(
              color: isStartOrDest
                  ? (n.id == path.first.id ? const Color(0xFF34D399) : const Color(0xFFF87171))
                  : (path.any((pn) => pn.id == n.id) ? Colors.white : Colors.white38),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          );
          final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 8));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FloorMapPainter oldDelegate) => true;
}
