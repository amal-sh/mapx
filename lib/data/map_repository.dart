import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';

/// Data-source-agnostic interface for reading and writing map graph data.
///
/// Phase 1 uses [LocalMapRepository] backed by local JSON file storage.
/// In Phase 8 (final phase), [FirestoreMapRepository] implements this same
/// interface for cloud synchronization and multi-device sharing.
abstract class MapRepository {
  // Buildings
  Future<List<Building>> getBuildings();
  Future<Building?> getBuilding(String buildingId);
  Future<void> saveBuilding(Building building);
  Future<void> deleteBuilding(String buildingId);

  // Floors
  Future<List<Floor>> getFloors(String buildingId);
  Future<Floor?> getFloor(String floorId);
  Future<void> saveFloor(Floor floor);
  Future<void> deleteFloor(String floorId);
  Future<void> clearFloorMap(String floorId);

  // Nodes
  Future<List<MapNode>> getNodes(String floorId);
  Future<MapNode?> getNode(String nodeId);
  Future<void> saveNode(MapNode node);
  Future<void> deleteNode(String nodeId);

  // Edges
  Future<List<MapEdge>> getEdges(String floorId);
  Future<void> saveEdge(MapEdge edge);
  Future<void> deleteEdge(String edgeId);

  // Export / Import
  Future<String> exportJson();
  Future<void> importJson(String jsonString);
}
