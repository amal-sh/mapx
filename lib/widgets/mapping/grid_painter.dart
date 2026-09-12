import 'package:flutter/material.dart';

import '../../models/edge.dart';
import '../../models/node.dart';

/// Canvas painter that visualizes placed nodes and connected edges in real time.
class GridPainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final MapNode? selectedNode;

  GridPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const scale = 25.0; // Pixels per meter

    final linePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final nodeMap = {for (final n in nodes) n.id: n};

    // Draw Edges
    for (final edge in edges) {
      final from = nodeMap[edge.fromNodeId];
      final to = nodeMap[edge.toNodeId];
      if (from == null || to == null) continue;

      final p1 = Offset(centerX + from.position.x * scale, centerY + from.position.z * scale);
      final p2 = Offset(centerX + to.position.x * scale, centerY + to.position.z * scale);

      canvas.drawLine(p1, p2, linePaint);
    }

    // Draw Nodes
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
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) => true;
}
