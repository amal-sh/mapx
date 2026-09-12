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
  });

  final Position position;
  final String suggestedLabel;
  final NodeType initialType;
  final void Function(String label, NodeType type) onConfirm;

  static void show({
    required BuildContext context,
    required Position position,
    required String suggestedLabel,
    required NodeType initialType,
    required void Function(String label, NodeType type) onConfirm,
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
      ),
    );
  }

  @override
  State<NodeFormDialog> createState() => _NodeFormDialogState();
}

class _NodeFormDialogState extends State<NodeFormDialog> {
  late final TextEditingController _labelController;
  late NodeType _selectedType;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.suggestedLabel);
    _selectedType = widget.initialType;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                  '(${widget.position.x.toStringAsFixed(1)}m, ${widget.position.z.toStringAsFixed(1)}m)',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
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
                widget.onConfirm(label, _selectedType);
              },
            ),
          ),
        ],
      ),
    );
  }
}
