import 'node.dart';

enum EdgeType { walkable, stair, elevator }

class MapEdge {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String floorId;
  final double weight;
  final EdgeType type;
  /// Exact physical footpath coordinates walked by the admin between fromNodeId and toNodeId.
  final List<Position>? footpath;

  const MapEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.floorId,
    required this.weight,
    required this.type,
    this.footpath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromNodeId': fromNodeId,
        'toNodeId': toNodeId,
        'floorId': floorId,
        'weight': weight,
        'type': type.name,
        if (footpath != null) 'footpath': footpath!.map((p) => p.toJson()).toList(),
      };

  factory MapEdge.fromJson(Map<String, dynamic> json) => MapEdge(
        id: json['id'] as String,
        fromNodeId: json['fromNodeId'] as String,
        toNodeId: json['toNodeId'] as String,
        floorId: json['floorId'] as String,
        weight: (json['weight'] as num).toDouble(),
        type: EdgeType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => EdgeType.walkable,
        ),
        footpath: json['footpath'] != null
            ? (json['footpath'] as List)
                .map((p) => Position.fromJson(p as Map<String, dynamic>))
                .toList()
            : null,
      );
}
