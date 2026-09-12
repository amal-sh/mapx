import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/building.dart';
import '../../models/floor.dart';

class BuildingCard extends StatelessWidget {
  const BuildingCard({
    super.key,
    required this.building,
    required this.floors,
    required this.onNavigate,
    required this.onAdminMap,
    required this.onDelete,
  });

  final Building building;
  final List<Floor> floors;
  final VoidCallback onNavigate;
  final VoidCallback onAdminMap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final floorSummary = floors.isEmpty
        ? 'No floors mapped'
        : floors.map((f) => f.name).join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E5EA), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(CupertinoIcons.building_2_fill, size: 22, color: Color(0xFF09090B)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          building.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          floorSummary,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18, color: Color(0xFF71717A)),
                    tooltip: 'Map options',
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.trash, size: 18, color: Color(0xFFDC2626)),
                            SizedBox(width: 10),
                            Text(
                              'Delete Map',
                              style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(CupertinoIcons.location_fill, size: 16),
                  label: const Text('Where do you want to go?'),
                  onPressed: floors.isEmpty ? null : onNavigate,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(CupertinoIcons.map, size: 16),
                  label: const Text('Admin AR Mapping Mode'),
                  onPressed: onAdminMap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
