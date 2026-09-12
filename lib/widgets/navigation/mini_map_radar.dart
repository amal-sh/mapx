import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../logic/bezier_smoother.dart';
import '../../models/edge.dart';
import '../../models/node.dart';
import '../../native/ar_bridge.dart';
import 'floor_map_view.dart';

/// Floating mini-map radar widget showing top-down floor layout with directional path arrows.
class MiniMapRadar extends StatelessWidget {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final List<MapNode> path;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final Vector3? userPosition;
  final VoidCallback onTap;

  const MiniMapRadar({
    super.key,
    required this.nodes,
    required this.edges,
    required this.path,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    this.userPosition,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.5),
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
              painter: FloorMapPainter(
                nodes: nodes,
                edges: edges,
                path: path,
                turnInstructions: turnInstructions,
                currentInstructionIndex: currentInstructionIndex,
                userPosition: userPosition,
                isMiniMap: true,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.fullscreen, color: Colors.white70, size: 12),
                    SizedBox(width: 2),
                    Text(
                      '2D',
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
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
}
