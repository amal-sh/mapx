import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MappingControlsBar extends StatelessWidget {
  const MappingControlsBar({
    super.key,
    required this.nodeCount,
    required this.isLinkingMode,
    required this.onAddNode,
    required this.onToggleLinkingMode,
    required this.onOpenInspector,
    this.distanceFromLastNode,
    this.isTorchOn = false,
    this.onToggleTorch,
    this.onUndo,
  });

  final int nodeCount;
  final bool isLinkingMode;
  final VoidCallback onAddNode;
  final VoidCallback onToggleLinkingMode;
  final VoidCallback onOpenInspector;
  final double? distanceFromLastNode;
  final bool isTorchOn;
  final VoidCallback? onToggleTorch;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final distLabel = distanceFromLastNode != null && nodeCount > 0
        ? ' (+${distanceFromLastNode!.toStringAsFixed(1)}m)'
        : '';

    return Card(
      color: Colors.black.withValues(alpha: 0.88),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Colors.white24, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            // 1. Add Node at Current Detected Position
            Expanded(
              flex: 3,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onAddNode,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.map_pin_ellipse, color: Color(0xFF38BDF8), size: 20),
                      const SizedBox(height: 3),
                      Text(
                        'Add Node$distLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Container(height: 24, width: 1, color: Colors.white12),

            // 2. Link Edge
            Expanded(
              flex: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: nodeCount < 2 ? null : onToggleLinkingMode,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.waveform_path,
                        color: nodeCount < 2
                            ? Colors.white38
                            : (isLinkingMode ? Colors.amberAccent : Colors.white70),
                        size: 20,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Link Edge',
                        style: TextStyle(
                          color: nodeCount < 2
                              ? Colors.white38
                              : (isLinkingMode ? Colors.amberAccent : Colors.white70),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (onToggleTorch != null) ...[
              Container(height: 24, width: 1, color: Colors.white12),
              // 3. Torch Toggle
              Expanded(
                flex: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onToggleTorch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTorchOn ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
                          color: isTorchOn ? Colors.amberAccent : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isTorchOn ? 'Torch On' : 'Torch',
                          style: TextStyle(
                            color: isTorchOn ? Colors.amberAccent : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            if (onUndo != null && nodeCount > 0) ...[
              Container(height: 24, width: 1, color: Colors.white12),
              // 4. Quick Undo
              Expanded(
                flex: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onUndo,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.arrow_uturn_left, color: Colors.white70, size: 20),
                        SizedBox(height: 3),
                        Text(
                          'Undo',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            Container(height: 24, width: 1, color: Colors.white12),

            // 5. Inspector / Node List
            Expanded(
              flex: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpenInspector,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.list_bullet, color: Colors.white, size: 20),
                      const SizedBox(height: 3),
                      Text(
                        '$nodeCount Nodes',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
