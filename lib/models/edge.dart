enum EdgeType { walkable, stair, elevator }

class MapEdge {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String floorId;
  final double weight;
  final EdgeType type;

  const MapEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.floorId,
    required this.weight,
    required this.type,
  });
}
