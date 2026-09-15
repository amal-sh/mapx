import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/local_map_repository.dart';
import '../data/map_repository.dart';
import '../models/building.dart';
import '../models/floor.dart';
import '../native/camera_permission.dart';
import '../widgets/home/add_building_dialog.dart';
import '../widgets/home/building_card.dart';
import '../widgets/home/empty_buildings_view.dart';
import '../widgets/home/floor_picker_sheet.dart';
import '../widgets/mapping/map_json_viewer_dialog.dart';
import 'admin_mapping_screen.dart';
import 'destination_select_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.repository});

  final MapRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final MapRepository _repo = widget.repository ?? LocalMapRepository();

  List<Building> _allBuildings = [];
  Map<String, List<Floor>> _buildingFloors = {};
  bool _loading = true;
  bool _permissionsGranted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestInitialPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsStatus();
    }
  }

  Future<void> _checkPermissionsStatus() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final allGranted = await checkAllAppPermissions();
    if (mounted) {
      setState(() => _permissionsGranted = allGranted);
    }
  }

  Future<void> _requestInitialPermissions() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final granted = await requestAllAppPermissions();
    if (mounted) {
      setState(() => _permissionsGranted = granted);
    }
  }

  Future<bool> _ensurePermissionsBeforeAction() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    final allGranted = await checkAllAppPermissions();
    if (allGranted) {
      if (!_permissionsGranted && mounted) {
        setState(() => _permissionsGranted = true);
      }
      return true;
    }

    final granted = await requestAllAppPermissions();
    if (mounted) {
      setState(() => _permissionsGranted = granted);
    }
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Camera & Activity Recognition permissions are required for AR navigation and spatial mapping.',
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFEF4444)),
          ),
          action: SnackBarAction(
            label: 'Settings',
            textColor: const Color(0xFF38BDF8),
            onPressed: openAppSettings,
          ),
        ),
      );
    }
    return granted;
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

  Future<void> _viewMapJson(Building building) async {
    final jsonString = await _repo.exportJson();
    if (!mounted) return;
    MapJsonViewerDialog.show(
      context: context,
      title: '${building.name} Map JSON',
      jsonString: jsonString,
    );
  }

  void _onNavigate(Building building, List<Floor> floors) async {
    final hasPerms = await _ensurePermissionsBeforeAction();
    if (!hasPerms || !mounted) return;

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
    final hasPerms = await _ensurePermissionsBeforeAction();
    if (!hasPerms || !mounted) return;

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
        final hasPerms = await _ensurePermissionsBeforeAction();
        if (!hasPerms || !mounted) return;

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

  Widget _buildPermissionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(CupertinoIcons.camera_viewfinder, color: Color(0xFF00E5FF), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AR & Motion Permissions Required',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  'Camera & Step Tracking are needed for AR navigation and spatial mapping.',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () async {
              final granted = await requestAllAppPermissions();
              if (!granted && mounted) {
                await openAppSettings();
              } else if (mounted) {
                setState(() => _permissionsGranted = granted);
              }
            },
            child: const Text('Grant'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Image.asset(
          'assets/images/mapx_logo_transp.png',
          height: 44,
          fit: BoxFit.contain,
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (!_permissionsGranted && !Platform.environment.containsKey('FLUTTER_TEST'))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _buildPermissionBanner(),
                    ),
                  Expanded(
                    child: _allBuildings.isEmpty
                        ? EmptyBuildingsView(onCreateBuilding: _showCreateBuildingDialog)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                            children: [
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
                                  onViewJson: () => _viewMapJson(building),
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
                ],
              ),
      ),
    );
  }
}
