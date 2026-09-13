import 'package:flutter/material.dart';

import '../../logic/spatial_odometry_tracker.dart';
import '../../models/edge.dart';
import '../../models/node.dart';

/// Canvas painter that visualizes placed nodes, connected edges,
/// live user tracking position, and continuous breadcrumb footsteps in real time.
class GridPainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final MapNode? selectedNode;
  final Position? currentUserPosition;
  final List<BreadcrumbPoint>? breadcrumbs;
  final double? headingRadians;

  GridPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    this.currentUserPosition,
    this.breadcrumbs,
    this.headingRadians,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const scale = 25.0; // Pixels per meter

    final linePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final nodeMap = {for (final n in nodes) n.id: n};

    // 1. Draw Edges
    for (final edge in edges) {
      final from = nodeMap[edge.fromNodeId];
      final to = nodeMap[edge.toNodeId];
      if (from == null || to == null) continue;

      final p1 = Offset(centerX + from.position.x * scale, centerY + from.position.z * scale);
      final p2 = Offset(centerX + to.position.x * scale, centerY + to.position.z * scale);

      canvas.drawLine(p1, p2, linePaint);
    }

    // 2. Draw Live Breadcrumb Footsteps
    if (breadcrumbs != null && breadcrumbs!.isNotEmpty) {
      final breadcrumbPaint = Paint()
        ..color = const Color(0xFF06B6D4).withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;

      for (int i = 0; i < breadcrumbs!.length; i++) {
        final b = breadcrumbs![i];
        final offset = Offset(centerX + b.position.x * scale, centerY + b.position.z * scale);
        canvas.drawCircle(offset, 2.5, breadcrumbPaint);
      }
    }

    // 3. Draw Placed Nodes
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final isSelected = selectedNode?.id == node.id;
      final offset = Offset(centerX + node.position.x * scale, centerY + node.position.z * scale);

      final nodePaint = Paint()
        ..color = isSelected
            ? const Color(0xFFF59E0B)
            : (node.type == NodeType.room ? const Color(0xFF2563EB) : const Color(0xFF10B981))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(offset, isSelected ? 9.0 : 6.5, nodePaint);

      // Label text
      final textSpan = TextSpan(
        text: node.label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(offset.dx - textPainter.width / 2, offset.dy + 8));
    }

    // 4. Draw Current User Odometry Marker (Active Tracking Pose)
    if (currentUserPosition != null) {
      final userOffset = Offset(
        centerX + currentUserPosition!.x * scale,
        centerY + currentUserPosition!.z * scale,
      );

      // Outer pulse ring
      final outerRing = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userOffset, 14.0, outerRing);

      // Inner dot
      final innerDot = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userOffset, 5.0, innerDot);

      // White border
      final borderPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(userOffset, 5.0, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) => true;
}
