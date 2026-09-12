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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(CupertinoIcons.compass, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'MapX',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'AR indoor navigation',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const Spacer(flex: 3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
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
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
