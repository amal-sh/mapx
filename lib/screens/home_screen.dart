import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/local_map_repository.dart';
import '../data/map_repository.dart';
import '../models/building.dart';
import '../models/floor.dart';
import '../widgets/home/add_building_dialog.dart';
import '../widgets/home/building_card.dart';
import '../widgets/home/empty_buildings_view.dart';
import '../widgets/home/floor_picker_sheet.dart';
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
    FloorPickerSheet.show(
      context: context,
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
      FloorPickerSheet.show(
        context: context,
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
    AddBuildingDialog.show(
      context: context,
      initialBuildingName: 'Block ${_allBuildings.length + 1}',
      onConfirm: (bName, fName) async {
        final bId = 'building_${DateTime.now().millisecondsSinceEpoch}';
        final fId = 'floor_${DateTime.now().millisecondsSinceEpoch}';

        final building = Building(id: bId, name: bName, entryFloorId: fId);
        final floor = Floor(id: fId, buildingId: bId, level: 0, name: fName);

        await _repo.saveBuilding(building);
        await _repo.saveFloor(floor);
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
                ? EmptyBuildingsView(onCreateBuilding: _showCreateBuildingDialog)
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
                        return BuildingCard(
                          building: building,
                          floors: floors,
                          onNavigate: () => _onNavigate(building, floors),
                          onAdminMap: () => _onAdminMap(building, floors),
                          onDelete: () => _confirmDeleteBuilding(building),
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
