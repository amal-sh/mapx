import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/local_map_repository.dart';
import '../data/map_repository.dart';
import '../models/building.dart';
import '../models/floor.dart';
import 'admin_mapping_screen.dart';
import 'destination_select_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.repository});

  final MapRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MapRepository _repo = widget.repository ?? LocalMapRepository();

  List<Building> _allBuildings = [];
  Map<String, List<Floor>> _buildingFloors = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final buildings = await _repo.getBuildings();
    final Map<String, List<Floor>> floorsMap = {};
    for (final b in buildings) {
      floorsMap[b.id] = await _repo.getFloors(b.id);
    }
    if (mounted) {
      setState(() {
        _allBuildings = buildings;
        _buildingFloors = floorsMap;
        _loading = false;
      });
    }
  }

  void _confirmDeleteBuilding(Building building) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Building Map?'),
        content: Text(
          'Are you sure you want to delete "${building.name}" and all its mapped floors, rooms, and paths? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final bId = building.id;
              final bName = building.name;
              Navigator.of(ctx).pop();
              setState(() => _loading = true);
              await _repo.deleteBuilding(bId);
              await _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted map for "$bName"'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            child: const Text('Delete Map'),
          ),
        ],
      ),
    );
  }

  void _showFloorPickerSheet({
    required Building building,
    required List<Floor> floors,
    required String title,
    required void Function(Floor) onFloorSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
                onTap: () {
                  Navigator.of(ctx).pop();
                  onFloorSelected(f);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNavigate(Building building, List<Floor> floors) {
    if (floors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No floors available to navigate. Use Admin Mapping to map a floor.')),
      );
      return;
    }
    if (floors.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DestinationSelectScreen(
            repository: _repo,
            floor: floors.first,
          ),
        ),
      );
      return;
    }
    _showFloorPickerSheet(
      building: building,
      floors: floors,
      title: 'Select Floor for Navigation',
      onFloorSelected: (selectedFloor) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DestinationSelectScreen(
              repository: _repo,
              floor: selectedFloor,
            ),
          ),
        );
      },
    );
  }

  void _onAdminMap(Building building, List<Floor> floors) async {
    final Floor targetFloor;
    if (floors.isEmpty) {
      final fId = 'floor_${DateTime.now().millisecondsSinceEpoch}';
      targetFloor = Floor(id: fId, buildingId: building.id, level: 0, name: 'Ground Floor');
      await _repo.saveFloor(targetFloor);
    } else if (floors.length == 1) {
      targetFloor = floors.first;
    } else {
      _showFloorPickerSheet(
        building: building,
        floors: floors,
        title: 'Select Floor to Map',
        onFloorSelected: (selectedFloor) async {
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AdminMappingScreen(
                repository: _repo,
                building: building,
                floor: selectedFloor,
              ),
            ),
          );
          _load();
        },
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminMappingScreen(
          repository: _repo,
          building: building,
          floor: targetFloor,
        ),
      ),
    );
    _load();
  }

  void _showCreateBuildingDialog() {
    final buildingController = TextEditingController(text: 'Block ${_allBuildings.length + 1}');
    final floorController = TextEditingController(text: 'Ground Floor');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Building'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: buildingController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Building Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF09090B), width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: floorController,
              decoration: InputDecoration(
                labelText: 'Floor Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF09090B), width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final bName = buildingController.text.trim().isEmpty
                  ? 'Building ${_allBuildings.length + 1}'
                  : buildingController.text.trim();
              final fName = floorController.text.trim().isEmpty ? 'Ground Floor' : floorController.text.trim();
              final bId = 'building_${DateTime.now().millisecondsSinceEpoch}';
              final fId = 'floor_${DateTime.now().millisecondsSinceEpoch}';

              final building = Building(id: bId, name: bName, entryFloorId: fId);
              final floor = Floor(id: fId, buildingId: bId, level: 0, name: fName);

              await _repo.saveBuilding(building);
              await _repo.saveFloor(floor);
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();

              if (mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminMappingScreen(
                      repository: _repo,
                      building: building,
                      floor: floor,
                    ),
                  ),
                );
                _load();
              }
            },
            child: const Text('Create & Map'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _allBuildings.isEmpty
                ? Padding(
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
                                    onPressed: _showCreateBuildingDialog,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF09090B),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(CupertinoIcons.compass, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MapX',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              Text(
                                'AR indoor navigation',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            icon: const Icon(CupertinoIcons.plus, size: 16),
                            label: const Text('Add Building'),
                            onPressed: _showCreateBuildingDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Mapped Buildings (${_allBuildings.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ..._allBuildings.map((building) {
                        final floors = _buildingFloors[building.id] ?? [];
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
                                            _confirmDeleteBuilding(building);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(CupertinoIcons.trash, size: 18, color: Color(0xFFDC2626)),
                                                SizedBox(width: 10),
                                                Text('Delete Map', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w500)),
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
                                      onPressed: floors.isEmpty ? null : () => _onNavigate(building, floors),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(CupertinoIcons.map, size: 16),
                                      label: const Text('Admin AR Mapping Mode'),
                                      onPressed: () => _onAdminMap(building, floors),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.plus, size: 16),
                        label: const Text('Add Another Building'),
                        onPressed: _showCreateBuildingDialog,
                      ),
                    ],
                  ),
      ),
    );
  }
}
