import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';

/// Data-source-agnostic interface for reading the map graph.
///
/// Phase 1 uses [HardcodedMapRepository]. Phase 7 swaps in a
/// Firestore-backed implementation of this same interface, so nothing
/// that consumes a MapRepository needs to change.
abstract class MapRepository {
  Future<List<Building>> getBuildings();
  Future<List<Floor>> getFloors(String buildingId);
  Future<List<MapNode>> getNodes(String floorId);
  Future<List<MapEdge>> getEdges(String floorId);
}
