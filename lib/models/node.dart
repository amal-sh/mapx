enum NodeType { room, junction, stair, elevator, doorway }

class Position {
  final double x;
  final double y;
  final double z;

  const Position({required this.x, required this.y, this.z = 0});
}

class MapNode {
  final String id;
  final String floorId;
  final NodeType type;
  final String label;
  final Position position;

  const MapNode({
    required this.id,
    required this.floorId,
    required this.type,
    required this.label,
    required this.position,
  });
}
