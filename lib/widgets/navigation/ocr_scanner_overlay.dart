import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../logic/ocr_matcher.dart';
import '../../models/node.dart';

/// Overlay shown when the user enters OCR Room Scan mode ("You Are Here").
/// Features a holographic HUD scanning reticle, animated laser beam,
/// real-time status feedback, and quick simulated door triggers for testing/demo.
class OcrScannerOverlay extends StatefulWidget {
  const OcrScannerOverlay({
    super.key,
    required this.candidateNodes,
    required this.onNodeMatched,
    required this.onClose,
    this.latestMatch,
  });

  final List<MapNode> candidateNodes;
  final ValueChanged<MapNode> onNodeMatched;
  final VoidCallback onClose;
  final OcrMatchResult? latestMatch;

  @override
  State<OcrScannerOverlay> createState() => _OcrScannerOverlayState();
}

class _OcrScannerOverlayState extends State<OcrScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanAnimationController;

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _scanAnimationController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMatch = widget.latestMatch != null;

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Stack(
          children: [
            // 1. Top Header & Close Button
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: IconButton(
                      icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 20),
                      onPressed: widget.onClose,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00E5FF),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'MLKit OCR Doorplate Scanner',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Point camera at room number or entrance sign',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Central Scanning Reticle
            Center(
              child: SizedBox(
                width: 280,
                height: 180,
                child: AnimatedBuilder(
                  animation: _scanAnimationController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ScannerReticlePainter(
                        progress: _scanAnimationController.value,
                        isMatched: hasMatch,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 3. Match Notification Badge
            if (hasMatch)
              Positioned(
                top: MediaQuery.of(context).size.height * 0.42,
                left: 32,
                right: 32,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF10B981), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.checkmark_seal_fill, color: Color(0xFF10B981), size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'MATCH DETECTED: ${widget.latestMatch!.node.label}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Confidence: ${(widget.latestMatch!.confidence * 100).toInt()}% • Raw: "${widget.latestMatch!.rawOcrText}"',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => widget.onNodeMatched(widget.latestMatch!.node),
                        child: const Text('Set Start', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),

            // 4. Quick Door Simulation Bar (for testing/demo/environments without physical door signs)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.bolt_fill, color: Color(0xFFF59E0B), size: 14),
                        const SizedBox(width: 6),
                        const Text(
                          'Test / Demo Doorplates (Tap to simulate OCR):',
                          style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.candidateNodes.take(6).map((node) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              backgroundColor: const Color(0xFF1E293B),
                              side: const BorderSide(color: Colors.white24),
                              label: Text(
                                node.label,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              onPressed: () {
                                widget.onNodeMatched(node);
                              },
                            ),
                          );
                        }).toList(),
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
}

class _ScannerReticlePainter extends CustomPainter {
  final double progress;
  final bool isMatched;

  _ScannerReticlePainter({required this.progress, required this.isMatched});

  @override
  void paint(Canvas canvas, Size size) {
    final primaryColor = isMatched ? const Color(0xFF10B981) : const Color(0xFF00E5FF);
    final cornerPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    const cornerLen = 28.0;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLen), cornerPaint);

    // Top-Right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLen, 0), cornerPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLen), cornerPaint);

    // Bottom-Left
    canvas.drawLine(Offset(0, size.height), Offset(cornerLen, size.height), cornerPaint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLen), cornerPaint);

    // Bottom-Right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLen, size.height), cornerPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLen), cornerPaint);

    // Moving scan laser line
    final scanY = size.height * progress;
    final laserPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          primaryColor.withValues(alpha: 0.0),
          primaryColor.withValues(alpha: 0.9),
          primaryColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, scanY - 2, size.width, 4))
      ..strokeWidth = 2.5;

    canvas.drawLine(Offset(8, scanY), Offset(size.width - 8, scanY), laserPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerReticlePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isMatched != isMatched;
  }
}
