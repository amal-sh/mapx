import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/hardcoded_map_repository.dart';
import 'package:mapx/logic/pathfinder.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('findPath on the hardcoded corridor', () {
    final repo = HardcodedMapRepository();

    test('returns the full corridor in order, entrance to stairs', () async {
      final nodes = await repo.getNodes('it-floor-0');
      final edges = await repo.getEdges('it-floor-0');

      final path = findPath(
        nodes: nodes,
        edges: edges,
        startNodeId: 'entrance',
        endNodeId: 'stairs-1',
      );

      expect(path.map((n) => n.id).toList(), [
        'entrance',
        'room-101',
        'room-102',
        'junction-mid',
        'room-103',
        'room-104',
        'stairs-1',
      ]);
    });

    test('returns a correct partial route to a mid-corridor room', () async {
      final nodes = await repo.getNodes('it-floor-0');
      final edges = await repo.getEdges('it-floor-0');

      final path = findPath(
        nodes: nodes,
        edges: edges,
        startNodeId: 'entrance',
        endNodeId: 'room-103',
      );

      expect(path.map((n) => n.id).toList(), [
        'entrance',
        'room-101',
        'room-102',
        'junction-mid',
        'room-103',
      ]);
    });
  });

  group('findPath edge cases', () {
    test('picks the lower-weight route over the fewer-hop route', () {
      // A --(20, 1 hop, straight line)-- D
      // A --3-- B --3-- C --4-- D   (3 hops, total 10 — cheaper)
      final nodes = [
        const MapNode(
          id: 'A',
          floorId: 'f',
          type: NodeType.junction,
          label: 'A',
          position: Position(x: 0, y: 0),
        ),
        const MapNode(
          id: 'B',
          floorId: 'f',
          type: NodeType.junction,
          label: 'B',
          position: Position(x: 3, y: 0),
        ),
        const MapNode(
          id: 'C',
          floorId: 'f',
          type: NodeType.junction,
          label: 'C',
          position: Position(x: 6, y: 0),
        ),
        const MapNode(
          id: 'D',
          floorId: 'f',
          type: NodeType.junction,
          label: 'D',
          position: Position(x: 10, y: 0),
        ),
      ];
      final edges = [
        const MapEdge(
          id: 'direct',
          fromNodeId: 'A',
          toNodeId: 'D',
          floorId: 'f',
          weight: 20,
          type: EdgeType.walkable,
        ),
        const MapEdge(
          id: 'ab',
          fromNodeId: 'A',
          toNodeId: 'B',
          floorId: 'f',
          weight: 3,
          type: EdgeType.walkable,
        ),
        const MapEdge(
          id: 'bc',
          fromNodeId: 'B',
          toNodeId: 'C',
          floorId: 'f',
          weight: 3,
          type: EdgeType.walkable,
        ),
        const MapEdge(
          id: 'cd',
          fromNodeId: 'C',
          toNodeId: 'D',
          floorId: 'f',
          weight: 4,
          type: EdgeType.walkable,
        ),
      ];

      final path = findPath(
        nodes: nodes,
        edges: edges,
        startNodeId: 'A',
        endNodeId: 'D',
      );

      expect(path.map((n) => n.id).toList(), ['A', 'B', 'C', 'D']);
    });

    test('returns an empty path when start and end are disconnected', () {
      final nodes = [
        const MapNode(
          id: 'E',
          floorId: 'f',
          type: NodeType.junction,
          label: 'E',
          position: Position(x: 0, y: 0),
        ),
        const MapNode(
          id: 'F',
          floorId: 'f',
          type: NodeType.junction,
          label: 'F',
          position: Position(x: 5, y: 0),
        ),
      ];

      final path = findPath(
        nodes: nodes,
        edges: const [],
        startNodeId: 'E',
        endNodeId: 'F',
      );

      expect(path, isEmpty);
    });

    test('returns a single-node path when start equals end', () async {
      final repo = HardcodedMapRepository();
      final nodes = await repo.getNodes('it-floor-0');
      final edges = await repo.getEdges('it-floor-0');

      final path = findPath(
        nodes: nodes,
        edges: edges,
        startNodeId: 'entrance',
        endNodeId: 'entrance',
      );

      expect(path.map((n) => n.id).toList(), ['entrance']);
    });

    test('returns an empty path for an unknown node id', () async {
      final repo = HardcodedMapRepository();
      final nodes = await repo.getNodes('it-floor-0');
      final edges = await repo.getEdges('it-floor-0');

      final path = findPath(
        nodes: nodes,
        edges: edges,
        startNodeId: 'entrance',
        endNodeId: 'does-not-exist',
      );

      expect(path, isEmpty);
    });
  });
}
