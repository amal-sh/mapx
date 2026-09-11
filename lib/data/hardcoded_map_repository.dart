import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';
import 'map_repository.dart';

/// Phase 1 test data: one real corridor, hand-measured (roughly) in meters.
/// Floor origin is the entrance junction; x/y are floor-local meters, z is
/// vertical (unused on this single-floor test area).
///
/// Swapped for a Firestore-backed [MapRepository] in Phase 7 without any
/// change to the code that consumes this interface.
class HardcodedMapRepository implements MapRepository {
  static const _building = Building(
    id: 'cusat-it',
    name: 'Dept. of IT, School of Engineering',
    entryFloorId: 'it-floor-0',
  );

  static const _floor = Floor(
    id: 'it-floor-0',
    buildingId: 'cusat-it',
    level: 0,
    name: 'Ground Floor',
  );

  static const _nodes = <MapNode>[
    MapNode(
      id: 'entrance',
      floorId: 'it-floor-0',
      type: NodeType.junction,
      label: 'Entrance',
      position: Position(x: 0, y: 0),
    ),
    MapNode(
      id: 'room-101',
      floorId: 'it-floor-0',
      type: NodeType.room,
      label: '101',
      position: Position(x: 3, y: 1.5),
    ),
    MapNode(
      id: 'room-102',
      floorId: 'it-floor-0',
      type: NodeType.room,
      label: '102',
      position: Position(x: 6, y: 1.5),
    ),
    MapNode(
      id: 'junction-mid',
      floorId: 'it-floor-0',
      type: NodeType.junction,
      label: 'Junction',
      position: Position(x: 9, y: 0),
    ),
    MapNode(
      id: 'room-103',
      floorId: 'it-floor-0',
      type: NodeType.room,
      label: '103',
      position: Position(x: 12, y: 1.5),
    ),
    MapNode(
      id: 'room-104',
      floorId: 'it-floor-0',
      type: NodeType.room,
      label: '104',
      position: Position(x: 15, y: 1.5),
    ),
    MapNode(
      id: 'stairs-1',
      floorId: 'it-floor-0',
      type: NodeType.stair,
      label: 'Stairs',
      position: Position(x: 18, y: 0),
    ),
  ];

  static const _edges = <MapEdge>[
    MapEdge(
      id: 'e1',
      fromNodeId: 'entrance',
      toNodeId: 'room-101',
      floorId: 'it-floor-0',
      weight: 3.35,
      type: EdgeType.walkable,
    ),
    MapEdge(
      id: 'e2',
      fromNodeId: 'room-101',
      toNodeId: 'room-102',
      floorId: 'it-floor-0',
      weight: 3.0,
      type: EdgeType.walkable,
    ),
    MapEdge(
      id: 'e3',
      fromNodeId: 'room-102',
      toNodeId: 'junction-mid',
      floorId: 'it-floor-0',
      weight: 3.35,
      type: EdgeType.walkable,
    ),
    MapEdge(
      id: 'e4',
      fromNodeId: 'junction-mid',
      toNodeId: 'room-103',
      floorId: 'it-floor-0',
      weight: 3.35,
      type: EdgeType.walkable,
    ),
    MapEdge(
      id: 'e5',
      fromNodeId: 'room-103',
      toNodeId: 'room-104',
      floorId: 'it-floor-0',
      weight: 3.0,
      type: EdgeType.walkable,
    ),
    MapEdge(
      id: 'e6',
      fromNodeId: 'room-104',
      toNodeId: 'stairs-1',
      floorId: 'it-floor-0',
      weight: 3.35,
      type: EdgeType.walkable,
    ),
  ];

  @override
  Future<List<Building>> getBuildings() async => const [_building];

  @override
  Future<List<Floor>> getFloors(String buildingId) async =>
      _floor.buildingId == buildingId ? const [_floor] : const [];

  @override
  Future<List<MapNode>> getNodes(String floorId) async =>
      _nodes.where((n) => n.floorId == floorId).toList();

  @override
  Future<List<MapEdge>> getEdges(String floorId) async =>
      _edges.where((e) => e.floorId == floorId).toList();
}
