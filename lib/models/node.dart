import 'dart:math' as math;

enum NodeType { room, junction, stair, elevator, doorway }

class Position {
  final double x;
  final double y;
  final double z;

  const Position({required this.x, required this.y, this.z = 0});

  double distanceTo(Position other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
      };

  factory Position.fromJson(Map<String, dynamic> json) => Position(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num? ?? 0).toDouble(),
      );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'floorId': floorId,
        'type': type.name,
        'label': label,
        'position': position.toJson(),
      };

  factory MapNode.fromJson(Map<String, dynamic> json) => MapNode(
        id: json['id'] as String,
        floorId: json['floorId'] as String,
        type: NodeType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => NodeType.room,
        ),
        label: json['label'] as String? ?? '',
        position: Position.fromJson(json['position'] as Map<String, dynamic>),
      );
}
