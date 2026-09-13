import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/node.dart';

class NodeFormDialog extends StatefulWidget {
  const NodeFormDialog({
    super.key,
    required this.position,
    required this.suggestedLabel,
    required this.initialType,
    required this.onConfirm,
    this.previousNodeLabel,
    this.previousNodePosition,
    this.initialDistance,
  });

  final Position position;
  final String suggestedLabel;
  final NodeType initialType;
  final void Function(String label, NodeType type, Position position) onConfirm;
  final String? previousNodeLabel;
  final Position? previousNodePosition;
  final double? initialDistance;

  static void show({
    required BuildContext context,
    required Position position,
    required String suggestedLabel,
    required NodeType initialType,
    required void Function(String label, NodeType type, Position position) onConfirm,
    String? previousNodeLabel,
    Position? previousNodePosition,
    double? initialDistance,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => NodeFormDialog(
        position: position,
        suggestedLabel: suggestedLabel,
        initialType: initialType,
        onConfirm: onConfirm,
        previousNodeLabel: previousNodeLabel,
        previousNodePosition: previousNodePosition,
        initialDistance: initialDistance,
      ),
    );
  }

  @override
  State<NodeFormDialog> createState() => _NodeFormDialogState();
}

class _NodeFormDialogState extends State<NodeFormDialog> {
  late final TextEditingController _labelController;
  late NodeType _selectedType;
  late Position _currentPosition;
  double? _distance;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.suggestedLabel);
    _selectedType = widget.initialType;
    _currentPosition = widget.position;

    if (widget.previousNodePosition != null) {
      _distance = widget.initialDistance ??
          widget.previousNodePosition!.distanceTo(widget.position);
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _adjustDistance(double delta) {
    if (_distance == null || widget.previousNodePosition == null) return;
    final newDistance = math.max(0.5, _distance! + delta);
    setState(() {
      _distance = double.parse(newDistance.toStringAsFixed(2));

      // Adjust _currentPosition along the vector from previous node
      final prev = widget.previousNodePosition!;
      final dx = _currentPosition.x - prev.x;
      final dz = _currentPosition.z - prev.z;
      final currentLen = math.sqrt(dx * dx + dz * dz);

      if (currentLen > 0.05) {
        final unitX = dx / currentLen;
        final unitZ = dz / currentLen;
        _currentPosition = Position(
          x: double.parse((prev.x + unitX * _distance!).toStringAsFixed(2)),
          y: 0.0,
          z: double.parse((prev.z + unitZ * _distance!).toStringAsFixed(2)),
        );
      } else {
        // If overlapping, push forward along Z
        _currentPosition = Position(
          x: prev.x,
          y: 0.0,
          z: double.parse((prev.z + _distance!).toStringAsFixed(2)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTooClose = _distance != null && _distance! < 0.8;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Place Spatial Node',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '(${_currentPosition.x.toStringAsFixed(1)}m, ${_currentPosition.z.toStringAsFixed(1)}m)',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          // Distance From Previous Node & Stepper Adjustment
          if (widget.previousNodeLabel != null && _distance != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isTooClose
                    ? const Color(0xFFFEF3C7)
                    : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isTooClose ? const Color(0xFFF59E0B) : const Color(0xFFE4E4E7),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isTooClose ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.arrow_right_arrow_left,
                        size: 16,
                        color: isTooClose ? const Color(0xFFD97706) : const Color(0xFF71717A),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Distance from "${widget.previousNodeLabel}":',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isTooClose ? const Color(0xFF92400E) : const Color(0xFF3F3F46),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(CupertinoIcons.minus_circle, size: 20),
                            onPressed: () => _adjustDistance(-0.5),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFD4D4D8)),
                            ),
                            child: Text(
                              '${_distance!.toStringAsFixed(2)}m',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(CupertinoIcons.plus_circle, size: 20),
                            onPressed: () => _adjustDistance(0.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isTooClose) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '⚠️ Nodes are too close (<0.8m) and may overlap. Tap "+" to space out or step forward.',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          TextField(
            controller: _labelController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Node Label / Room Number',
              hintText: 'e.g. 101, Lab 2, Main Entrance',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF09090B), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Node Type',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: NodeType.values.map((type) {
              final isSelected = _selectedType == type;
              return ChoiceChip(
                label: Text(type.name.toUpperCase()),
                selected: isSelected,
                selectedColor: const Color(0xFF09090B),
                backgroundColor: const Color(0xFFF4F4F5),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF09090B),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (val) {
                  if (val) setState(() => _selectedType = type);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(CupertinoIcons.map_pin_ellipse, size: 18),
              label: const Text('Confirm & Drop Node'),
              onPressed: () {
                final label = _labelController.text.trim().isEmpty
                    ? widget.suggestedLabel
                    : _labelController.text.trim();
                Navigator.of(context).pop();
                widget.onConfirm(label, _selectedType, _currentPosition);
              },
            ),
          ),
        ],
      ),
    );
  }
}
