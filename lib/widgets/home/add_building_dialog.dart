import 'package:flutter/material.dart';

class AddBuildingDialog extends StatefulWidget {
  const AddBuildingDialog({
    super.key,
    required this.initialBuildingName,
    required this.onConfirm,
  });

  final String initialBuildingName;
  final Future<void> Function(String buildingName, String floorName) onConfirm;

  static Future<void> show({
    required BuildContext context,
    required String initialBuildingName,
    required Future<void> Function(String buildingName, String floorName) onConfirm,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AddBuildingDialog(
        initialBuildingName: initialBuildingName,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<AddBuildingDialog> createState() => _AddBuildingDialogState();
}

class _AddBuildingDialogState extends State<AddBuildingDialog> {
  late final TextEditingController _buildingController;
  late final TextEditingController _floorController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _buildingController = TextEditingController(text: widget.initialBuildingName);
    _floorController = TextEditingController(text: 'Ground Floor');
  }

  @override
  void dispose() {
    _buildingController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final bName = _buildingController.text.trim().isEmpty
        ? widget.initialBuildingName
        : _buildingController.text.trim();
    final fName = _floorController.text.trim().isEmpty
        ? 'Ground Floor'
        : _floorController.text.trim();

    Navigator.of(context).pop();
    await widget.onConfirm(bName, fName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Building'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _buildingController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Building Name',
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
          const SizedBox(height: 12),
          TextField(
            controller: _floorController,
            decoration: InputDecoration(
              labelText: 'Floor Name',
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Create & Map'),
        ),
      ],
    );
  }
}
