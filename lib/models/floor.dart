import 'node.dart';

class Floor {
  final String id;
  final String buildingId;
  final int level;
  final String name;
  final Position? originAnchor;

  const Floor({
    required this.id,
    required this.buildingId,
    required this.level,
    required this.name,
    this.originAnchor,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'buildingId': buildingId,
        'level': level,
        'name': name,
        if (originAnchor != null) 'originAnchor': originAnchor!.toJson(),
      };

  factory Floor.fromJson(Map<String, dynamic> json) => Floor(
        id: json['id'] as String,
        buildingId: json['buildingId'] as String,
        level: (json['level'] as num?)?.toInt() ?? 0,
        name: json['name'] as String,
        originAnchor: json['originAnchor'] != null
            ? Position.fromJson(json['originAnchor'] as Map<String, dynamic>)
            : null,
      );
}
