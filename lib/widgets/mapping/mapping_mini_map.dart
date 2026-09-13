import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../logic/spatial_odometry_tracker.dart';
import '../../models/edge.dart';
import '../../models/node.dart';

/// Floating Mini-Map Radar widget for the AR Mapping Screen.
/// Displays a top-down bird's-eye overview of placed nodes, connected paths,
/// live user position, and directional camera heading FOV cone.
/// Tapping expands it into a full interactive 2D floor inspection view.
class MappingMiniMap extends StatelessWidget {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final Position currentUserPosition;
  final double headingRadians;
  final MapNode? selectedNode;
  final List<BreadcrumbPoint>? breadcrumbs;
  final VoidCallback? onExpand;

  const MappingMiniMap({
    super.key,
    required this.nodes,
    required this.edges,
    required this.currentUserPosition,
    required this.headingRadians,
    this.selectedNode,
    this.breadcrumbs,
    this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (onExpand != null) {
          onExpand!();
        } else {
          _showFullscreenFloorOverview(context);
        }
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF090D16).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomPaint(
              size: const Size(120, 120),
              painter: _MiniMapPainter(
                nodes: nodes,
                edges: edges,
                currentUserPosition: currentUserPosition,
                headingRadians: headingRadians,
                selectedNode: selectedNode,
                breadcrumbs: breadcrumbs,
              ),
            ),
            // Radar overlay badge
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.fullscreen, color: Colors.white70, size: 10),
                    SizedBox(width: 3),
                    Text(
                      '2D',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreenFloorOverview(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF090D16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '2D Floor Map Overview',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${nodes.length} nodes • ${edges.length} paths',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white54),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF050811),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CustomPaint(
                          painter: _MiniMapPainter(
                            nodes: nodes,
                            edges: edges,
                            currentUserPosition: currentUserPosition,
                            headingRadians: headingRadians,
                            selectedNode: selectedNode,
                            breadcrumbs: breadcrumbs,
                            isEnlarged: true,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final Position currentUserPosition;
  final double headingRadians;
  final MapNode? selectedNode;
  final List<BreadcrumbPoint>? breadcrumbs;
  final bool isEnlarged;

  _MiniMapPainter({
    required this.nodes,
    required this.edges,
    required this.currentUserPosition,
    required this.headingRadians,
    this.selectedNode,
    this.breadcrumbs,
    this.isEnlarged = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw subtle background radar grid
    final gridPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    final cx = size.width / 2;
    final cy = size.height / 2;

    for (double r = 20; r < size.width; r += 25) {
      canvas.drawCircle(Offset(cx, cy), r, gridPaint);
    }
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), gridPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), gridPaint);

    // 2. Compute bounding bounds centered around current user position
    double minX = currentUserPosition.x;
    double maxX = currentUserPosition.x;
    double minZ = currentUserPosition.z;
    double maxZ = currentUserPosition.z;

    for (final n in nodes) {
      if (n.position.x < minX) minX = n.position.x;
      if (n.position.x > maxX) maxX = n.position.x;
      if (n.position.z < minZ) minZ = n.position.z;
      if (n.position.z > maxZ) maxZ = n.position.z;
    }

    if (breadcrumbs != null) {
      for (final b in breadcrumbs!) {
        if (b.position.x < minX) minX = b.position.x;
        if (b.position.x > maxX) maxX = b.position.x;
        if (b.position.z < minZ) minZ = b.position.z;
        if (b.position.z > maxZ) maxZ = b.position.z;
      }
    }

    final pad = isEnlarged ? 40.0 : 16.0;
    final spanX = math.max(12.0, (maxX - minX) * 1.4);
    final spanZ = math.max(12.0, (maxZ - minZ) * 1.4);

    final scaleX = (size.width - pad * 2) / spanX;
    final scaleZ = (size.height - pad * 2) / spanZ;
    final scale = math.min(scaleX, scaleZ);

    final midX = (minX + maxX) / 2;
    final midZ = (minZ + maxZ) / 2;

    Offset toScreen(double x, double z) {
      final dx = (x - midX) * scale;
      final dz = (z - midZ) * scale;
      return Offset(cx + dx, cy + dz);
    }

    final nodeMap = {for (final n in nodes) n.id: n};

    // 2.5 Draw Breadcrumbs (Walked Footsteps)
    if (breadcrumbs != null && breadcrumbs!.isNotEmpty) {
      final trailPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.55)
        ..strokeWidth = isEnlarged ? 2.0 : 1.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final dotPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.fill;

      Offset? prev;
      for (final b in breadcrumbs!) {
        final pt = toScreen(b.position.x, b.position.z);
        if (prev != null) {
          canvas.drawLine(prev, pt, trailPaint);
        }
        prev = pt;
        canvas.drawCircle(pt, isEnlarged ? 2.5 : 1.5, dotPaint);
      }
    }

    // 3. Draw Edges
    final edgePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.65)
      ..strokeWidth = isEnlarged ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final from = nodeMap[edge.fromNodeId];
      final to = nodeMap[edge.toNodeId];
      if (from == null || to == null) continue;

      final p1 = toScreen(from.position.x, from.position.z);
      final p2 = toScreen(to.position.x, to.position.z);
      canvas.drawLine(p1, p2, edgePaint);
    }

    // 4. Draw Placed Nodes
    for (final node in nodes) {
      final isSelected = selectedNode?.id == node.id;
      final pos = toScreen(node.position.x, node.position.z);

      Color color;
      switch (node.type) {
        case NodeType.room:
          color = const Color(0xFF3B82F6);
          break;
        case NodeType.junction:
          color = const Color(0xFF10B981);
          break;
        case NodeType.stair:
          color = const Color(0xFFF97316);
          break;
        case NodeType.elevator:
          color = const Color(0xFF8B5CF6);
          break;
        default:
          color = const Color(0xFF64748B);
      }

      if (isSelected) color = const Color(0xFFF59E0B);

      final nodeRadius = isEnlarged ? (isSelected ? 8.0 : 6.0) : (isSelected ? 5.5 : 4.0);
      canvas.drawCircle(
        pos,
        nodeRadius,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pos,
        nodeRadius,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );

      if (isEnlarged) {
        final textSpan = TextSpan(
          text: node.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        );
        final painter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
        painter.paint(canvas, Offset(pos.dx - painter.width / 2, pos.dy + 8));
      }
    }

    // 5. Draw User Position & Directional Heading FOV Vision Cone
    final userPos = toScreen(currentUserPosition.x, currentUserPosition.z);

    // Directional Vision Cone (FOV fan)
    final fovAngle = math.pi / 4; // 45 degrees FOV
    final coneLength = isEnlarged ? 45.0 : 25.0;

    final conePath = Path()..moveTo(userPos.dx, userPos.dy);
    // Heading 0 is +Z (down in screen coords), pi/2 is +X (right in screen coords)
    final h1 = headingRadians - fovAngle / 2;
    final h2 = headingRadians + fovAngle / 2;

    conePath.lineTo(userPos.dx + math.sin(h1) * coneLength, userPos.dy + math.cos(h1) * coneLength);
    conePath.arcToPoint(
      Offset(userPos.dx + math.sin(h2) * coneLength, userPos.dy + math.cos(h2) * coneLength),
      radius: Radius.circular(coneLength),
    );
    conePath.close();

    final conePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.45),
          const Color(0xFF10B981).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: userPos, radius: coneLength))
      ..style = PaintingStyle.fill;
    canvas.drawPath(conePath, conePaint);

    // User dot outer halo
    canvas.drawCircle(
      userPos,
      isEnlarged ? 9.0 : 6.0,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );

    // User dot center
    canvas.drawCircle(
      userPos,
      isEnlarged ? 4.5 : 3.0,
      Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      userPos,
      isEnlarged ? 4.5 : 3.0,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
