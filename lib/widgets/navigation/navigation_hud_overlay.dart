import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../logic/bezier_smoother.dart';
import '../../models/floor.dart';
import '../../models/node.dart';

class NavigationHudOverlay extends StatelessWidget {
  final MapNode? selectedStartNode;
  final TurnInstruction? currentInstruction;
  final int currentInstructionIndex;
  final int totalInstructionsCount;
  final double currentStepRemainingDistance;
  final double totalDistance;
  final MapNode destination;
  final Floor floor;
  final String? obstacleWarning;
  final bool hasReachedDestination;
  final VoidCallback onSelectStartLocation;
  final VoidCallback onNextStep;
  final VoidCallback? onFinishNavigation;

  const NavigationHudOverlay({
    super.key,
    required this.selectedStartNode,
    required this.currentInstruction,
    required this.currentInstructionIndex,
    required this.totalInstructionsCount,
    required this.currentStepRemainingDistance,
    required this.totalDistance,
    required this.destination,
    required this.floor,
    this.obstacleWarning,
    this.hasReachedDestination = false,
    required this.onSelectStartLocation,
    required this.onNextStep,
    this.onFinishNavigation,
  });

  IconData _getTurnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('start')) return CupertinoIcons.location_north_fill;
    if (lower.contains('arrive')) return CupertinoIcons.check_mark_circled_solid;
    if (lower.contains('slight left')) return CupertinoIcons.arrow_up_left;
    if (lower.contains('slight right')) return CupertinoIcons.arrow_up_right;
    if (lower.contains('left')) return CupertinoIcons.arrow_turn_up_left;
    if (lower.contains('right')) return CupertinoIcons.arrow_turn_up_right;
    if (lower.contains('stair')) return CupertinoIcons.arrow_up_right;
    if (lower.contains('elevator')) return CupertinoIcons.arrow_up_arrow_down;
    return CupertinoIcons.arrow_up;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Celebratory Destination Reached Card
        if (hasReachedDestination)
          Card(
            color: const Color(0xFF09090B).withValues(alpha: 0.94),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                    ),
                    child: const Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      size: 26,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Destination Reached!',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'You have arrived at ${destination.label}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onFinishNavigation != null)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: onFinishNavigation,
                      child: const Text('Finish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                ],
              ),
            ),
          )
        // Prompt Banner when starting location is not yet chosen
        else if (selectedStartNode == null)
          Card(
            color: const Color(0xFF09090B).withValues(alpha: 0.94),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.location_fill, color: Color(0xFF10B981), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Current Location',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Choose your starting point on ${floor.name} to navigate to ${destination.label}.',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(CupertinoIcons.placemark, size: 18),
                      label: const Text('Choose Starting Location', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: onSelectStartLocation,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Floating Turn-by-Turn Guidance HUD
        if (!hasReachedDestination && selectedStartNode != null && currentInstruction != null)
          Card(
            color: const Color(0xFF09090B).withValues(alpha: 0.94),
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Start Location & Change Chip
                  GestureDetector(
                    onTap: onSelectStartLocation,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.location_north_fill, color: Color(0xFF10B981), size: 11),
                          const SizedBox(width: 4),
                          Text(
                            'From: ${selectedStartNode!.label}',
                            style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Change',
                            style: TextStyle(color: Colors.white60, fontSize: 10, decoration: TextDecoration.underline),
                          ),
                          const SizedBox(width: 2),
                          const Icon(CupertinoIcons.chevron_down, color: Colors.white60, size: 9),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getTurnIcon(currentInstruction!.instruction),
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentInstruction!.instruction,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${currentStepRemainingDistance.toStringAsFixed(1)}m • Total: ${totalDistance.toStringAsFixed(1)}m to ${destination.label}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (totalInstructionsCount > 1)
                        IconButton(
                          tooltip: currentInstructionIndex < totalInstructionsCount - 1
                              ? 'Next Step'
                              : 'Arrive at Destination',
                          icon: Icon(
                            currentInstructionIndex < totalInstructionsCount - 1
                                ? CupertinoIcons.forward_end_fill
                                : CupertinoIcons.checkmark_circle_fill,
                            color: currentInstructionIndex < totalInstructionsCount - 1
                                ? Colors.white70
                                : const Color(0xFF10B981),
                            size: 20,
                          ),
                          onPressed: onNextStep,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Dynamic Obstacle Warning Banner
        if (obstacleWarning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    obstacleWarning!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
