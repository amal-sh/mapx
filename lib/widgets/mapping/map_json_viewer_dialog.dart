import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modal dialog that renders the exact formatted JSON representation
/// of the indoor map (buildings, floors, nodes, edges, and physical footpaths).
class MapJsonViewerDialog extends StatelessWidget {
  final String title;
  final String jsonString;

  const MapJsonViewerDialog({
    super.key,
    required this.title,
    required this.jsonString,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String jsonString,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => MapJsonViewerDialog(
        title: title,
        jsonString: jsonString,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Parse stats if valid JSON
    int nodeCount = 0;
    int edgeCount = 0;
    int footpathCount = 0;
    try {
      final decoded = json.decode(jsonString);
      if (decoded is Map<String, dynamic>) {
        if (decoded['nodes'] is List) nodeCount = (decoded['nodes'] as List).length;
        if (decoded['edges'] is List) {
          final edgesList = decoded['edges'] as List;
          edgeCount = edgesList.length;
          for (final e in edgesList) {
            if (e is Map<String, dynamic> && e['footpath'] is List) {
              footpathCount += (e['footpath'] as List).length;
            }
          }
        }
      }
    } catch (_) {}

    final lineCount = jsonString.split('\n').length;
    final sizeKb = (jsonString.length / 1024).toStringAsFixed(1);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      CupertinoIcons.doc_text_search,
                      color: Color(0xFF00E5FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '$lineCount lines • $sizeKb KB • $nodeCount nodes • $edgeCount edges',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy JSON',
                    icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonString));
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📋 Map JSON copied to clipboard!'),
                          duration: Duration(milliseconds: 1400),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Metadata Chips
            if (footpathCount > 0 || nodeCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _chip(
                      label: '$nodeCount Landmarks',
                      icon: CupertinoIcons.placemark,
                      color: const Color(0xFF10B981),
                    ),
                    _chip(
                      label: '$edgeCount Graph Edges',
                      icon: CupertinoIcons.shuffle,
                      color: const Color(0xFF38BDF8),
                    ),
                    if (footpathCount > 0)
                      _chip(
                        label: '$footpathCount Exact Footsteps Walked',
                        icon: CupertinoIcons.circle_grid_hex,
                        color: const Color(0xFFA855F7),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Code View Container
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF030712) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: SelectionArea(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        jsonString,
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          height: 1.45,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Footer Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonString));
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📋 Map JSON copied to clipboard!'),
                          duration: Duration(milliseconds: 1400),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 16),
                    label: const Text('Copy JSON'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF09090B),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
