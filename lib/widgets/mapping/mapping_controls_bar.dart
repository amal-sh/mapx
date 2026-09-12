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
  });

  final int nodeCount;
  final bool isLinkingMode;
  final VoidCallback onAddNode;
  final VoidCallback onToggleLinkingMode;
  final VoidCallback onOpenInspector;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onAddNode,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.map_pin_ellipse, color: Colors.white, size: 20),
                      SizedBox(height: 3),
                      Text(
                        'Add Node',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(height: 24, width: 1, color: Colors.white24),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: nodeCount < 2 ? null : onToggleLinkingMode,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.waveform_path,
                        color: nodeCount < 2
                            ? Colors.white38
                            : (isLinkingMode ? Colors.white : Colors.white70),
                        size: 20,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Link Edge',
                        style: TextStyle(
                          color: nodeCount < 2
                              ? Colors.white38
                              : (isLinkingMode ? Colors.white : Colors.white70),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(height: 24, width: 1, color: Colors.white24),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpenInspector,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.list_bullet, color: Colors.white, size: 20),
                      SizedBox(height: 3),
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
