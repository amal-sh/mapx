import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';
import 'map_repository.dart';

/// Local JSON-backed implementation of [MapRepository].
///
/// Stores building, floor, node, and edge graphs in a local JSON file.
/// Supports in-memory initialization and custom file paths for unit tests.
class LocalMapRepository implements MapRepository {
  LocalMapRepository({File? storageFile}) : _customFile = storageFile;

  final File? _customFile;
  File? _file;
  bool _initialized = false;

  final Map<String, Building> _buildings = {};
  final Map<String, Floor> _floors = {};
  final Map<String, MapNode> _nodes = {};
  final Map<String, MapEdge> _edges = {};

  Future<File> _resolveFile() async {
    if (_customFile != null) return _customFile;
    if (_file != null) return _file!;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _file = File('mapx_local_data_test.json');
      return _file!;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/mapx_local_data.json');
    } catch (_) {
      // Fallback for desktop/test run without path_provider binding
      _file = File('mapx_local_data.json');
    }
    return _file!;
  }

  Future<void> _ensureLoaded() async {
    if (_initialized) return;
    _initialized = true;

    final file = await _resolveFile();
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          _parseJson(content);
          return;
        }
      } catch (e) {
        // Corrupted or unreadable, fall back to seed data
      }
    }

    _buildings.clear();
    _floors.clear();
    _nodes.clear();
    _edges.clear();
    await _saveToFile();
  }

  void _parseJson(String jsonString) {
    final Map<String, dynamic> data = json.decode(jsonString) as Map<String, dynamic>;

    _buildings.clear();
    _floors.clear();
    _nodes.clear();
    _edges.clear();

    if (data['buildings'] is List) {
      for (final item in data['buildings'] as List) {
        final b = Building.fromJson(item as Map<String, dynamic>);
        _buildings[b.id] = b;
      }
    }

    if (data['floors'] is List) {
      for (final item in data['floors'] as List) {
        final f = Floor.fromJson(item as Map<String, dynamic>);
        _floors[f.id] = f;
      }
    }

    if (data['nodes'] is List) {
      for (final item in data['nodes'] as List) {
        final n = MapNode.fromJson(item as Map<String, dynamic>);
        _nodes[n.id] = n;
      }
    }

    if (data['edges'] is List) {
      for (final item in data['edges'] as List) {
        final e = MapEdge.fromJson(item as Map<String, dynamic>);
        _edges[e.id] = e;
      }
    }
  }

  Map<String, dynamic> _toMap() => {
        'buildings': _buildings.values.map((b) => b.toJson()).toList(),
        'floors': _floors.values.map((f) => f.toJson()).toList(),
        'nodes': _nodes.values.map((n) => n.toJson()).toList(),
        'edges': _edges.values.map((e) => e.toJson()).toList(),
      };

  Future<void> _saveToFile() async {
    final file = await _resolveFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(_toMap()));
  }

  // --- Building Methods ---

  @override
  Future<List<Building>> getBuildings() async {
    await _ensureLoaded();
    return _buildings.values.toList();
  }

  @override
  Future<Building?> getBuilding(String buildingId) async {
    await _ensureLoaded();
    return _buildings[buildingId];
  }

  @override
  Future<void> saveBuilding(Building building) async {
    await _ensureLoaded();
    _buildings[building.id] = building;
    await _saveToFile();
  }

  @override
  Future<void> deleteBuilding(String buildingId) async {
    await _ensureLoaded();
    _buildings.remove(buildingId);

    final floorsToDelete = _floors.values
        .where((f) => f.buildingId == buildingId)
        .map((f) => f.id)
        .toList();

    for (final fId in floorsToDelete) {
      await deleteFloor(fId);
    }

    await _saveToFile();
  }

  // --- Floor Methods ---

  @override
  Future<List<Floor>> getFloors(String buildingId) async {
    await _ensureLoaded();
    return _floors.values.where((f) => f.buildingId == buildingId).toList();
  }

  @override
  Future<Floor?> getFloor(String floorId) async {
    await _ensureLoaded();
    return _floors[floorId];
  }

  @override
  Future<void> saveFloor(Floor floor) async {
    await _ensureLoaded();
    _floors[floor.id] = floor;
    await _saveToFile();
  }

  @override
  Future<void> deleteFloor(String floorId) async {
    await _ensureLoaded();
    _floors.remove(floorId);
    _nodes.removeWhere((_, n) => n.floorId == floorId);
    _edges.removeWhere((_, e) => e.floorId == floorId);
    await _saveToFile();
  }

  @override
  Future<void> clearFloorMap(String floorId) async {
    await _ensureLoaded();
    _nodes.removeWhere((_, n) => n.floorId == floorId);
    _edges.removeWhere((_, e) => e.floorId == floorId);
    final floor = _floors[floorId];
    if (floor != null && floor.originAnchor != null) {
      _floors[floorId] = Floor(
        id: floor.id,
        buildingId: floor.buildingId,
        level: floor.level,
        name: floor.name,
        originAnchor: null,
      );
    }
    await _saveToFile();
  }

  // --- Node Methods ---

  @override
  Future<List<MapNode>> getNodes(String floorId) async {
    await _ensureLoaded();
    return _nodes.values.where((n) => n.floorId == floorId).toList();
  }

  @override
  Future<MapNode?> getNode(String nodeId) async {
    await _ensureLoaded();
    return _nodes[nodeId];
  }

  @override
  Future<void> saveNode(MapNode node) async {
    await _ensureLoaded();
    _nodes[node.id] = node;
    await _saveToFile();
  }

  @override
  Future<void> deleteNode(String nodeId) async {
    await _ensureLoaded();
    _nodes.remove(nodeId);
    // Remove all edges connected to this node
    _edges.removeWhere(
      (_, e) => e.fromNodeId == nodeId || e.toNodeId == nodeId,
    );
    await _saveToFile();
  }

  // --- Edge Methods ---

  @override
  Future<List<MapEdge>> getEdges(String floorId) async {
    await _ensureLoaded();
    return _edges.values.where((e) => e.floorId == floorId).toList();
  }

  @override
  Future<void> saveEdge(MapEdge edge) async {
    await _ensureLoaded();
    _edges[edge.id] = edge;
    await _saveToFile();
  }

  @override
  Future<void> deleteEdge(String edgeId) async {
    await _ensureLoaded();
    _edges.remove(edgeId);
    await _saveToFile();
  }

  // --- Export / Import ---

  @override
  Future<String> exportJson() async {
    await _ensureLoaded();
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_toMap());
  }

  @override
  Future<void> importJson(String jsonString) async {
    _parseJson(jsonString);
    _initialized = true;
    await _saveToFile();
  }
}
