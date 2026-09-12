import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/building.dart';
import '../../models/floor.dart';

class FloorPickerSheet extends StatelessWidget {
  const FloorPickerSheet({
    super.key,
    required this.building,
    required this.floors,
    required this.title,
    required this.onFloorSelected,
  });

  final Building building;
  final List<Floor> floors;
  final String title;
  final ValueChanged<Floor> onFloorSelected;

  static void show({
    required BuildContext context,
    required Building building,
    required List<Floor> floors,
    required String title,
    required ValueChanged<Floor> onFloorSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FloorPickerSheet(
        building: building,
        floors: floors,
        title: title,
        onFloorSelected: (f) {
          Navigator.of(ctx).pop();
          onFloorSelected(f);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD4D4D8),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            building.name,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...floors.map(
            (f) => ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(CupertinoIcons.square_stack_3d_up, size: 20),
              title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Level ${f.level}', style: const TextStyle(color: Color(0xFF71717A))),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: Color(0xFFA1A1AA)),
              onTap: () => onFloorSelected(f),
            ),
          ),
        ],
      ),
    );
  }
}
