class Building {
  final String id;
  final String name;
  final String entryFloorId;

  const Building({
    required this.id,
    required this.name,
    required this.entryFloorId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'entryFloorId': entryFloorId,
      };

  factory Building.fromJson(Map<String, dynamic> json) => Building(
        id: json['id'] as String,
        name: json['name'] as String,
        entryFloorId: json['entryFloorId'] as String? ?? '',
      );
}
