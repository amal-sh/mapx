import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class EmptyBuildingsView extends StatelessWidget {
  const EmptyBuildingsView({
    super.key,
    required this.onCreateBuilding,
  });

  final VoidCallback onCreateBuilding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(CupertinoIcons.building_2_fill, size: 32, color: Color(0xFF09090B)),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Buildings Mapped',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Start by creating a building and mapping its floors in AR.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(CupertinoIcons.plus, size: 18),
                    label: const Text('Create & Map Building'),
                    onPressed: onCreateBuilding,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
