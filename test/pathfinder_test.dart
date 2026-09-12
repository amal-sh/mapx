import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/logic/pathfinder.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/node.dart';

void main() {
  final testNodes = [
    const MapNode(id: 'entrance', floorId: 'it-floor-0', type: NodeType.junction, label: 'Entrance', position: Position(x: 0, y: 0)),
    const MapNode(id: 'room-101', floorId: 'it-floor-0', type: NodeType.room, label: '101', position: Position(x: 3, y: 1.5)),
    const MapNode(id: 'room-102', floorId: 'it-floor-0', type: NodeType.room, label: '102', position: Position(x: 6, y: 1.5)),
    const MapNode(id: 'junction-mid', floorId: 'it-floor-0', type: NodeType.junction, label: 'Junction', position: Position(x: 9, y: 0)),
    const MapNode(id: 'room-103', floorId: 'it-floor-0', type: NodeType.room, label: '103', position: Position(x: 12, y: 1.5)),
    const MapNode(id: 'room-104', floorId: 'it-floor-0', type: NodeType.room, label: '104', position: Position(x: 15, y: 1.5)),
    const MapNode(id: 'stairs-1', floorId: 'it-floor-0', type: NodeType.stair, label: 'Stairs', position: Position(x: 18, y: 0)),
  ];

  final testEdges = [
    const MapEdge(id: 'e1', fromNodeId: 'entrance', toNodeId: 'room-101', floorId: 'it-floor-0', weight: 3.35, type: EdgeType.walkable),
    const MapEdge(id: 'e2', fromNodeId: 'room-101', toNodeId: 'room-102', floorId: 'it-floor-0', weight: 3.0, type: EdgeType.walkable),
    const MapEdge(id: 'e3', fromNodeId: 'room-102', toNodeId: 'junction-mid', floorId: 'it-floor-0', weight: 3.35, type: EdgeType.walkable),
    const MapEdge(id: 'e4', fromNodeId: 'junction-mid', toNodeId: 'room-103', floorId: 'it-floor-0', weight: 3.35, type: EdgeType.walkable),
    const MapEdge(id: 'e5', fromNodeId: 'room-103', toNodeId: 'room-104', floorId: 'it-floor-0', weight: 3.0, type: EdgeType.walkable),
    const MapEdge(id: 'e6', fromNodeId: 'room-104', toNodeId: 'stairs-1', floorId: 'it-floor-0', weight: 3.35, type: EdgeType.walkable),
  ];

  group('findPath on sample corridor graph', () {
    test('returns the full corridor in order, entrance to stairs', () {
      final path = findPath(
        nodes: testNodes,
        edges: testEdges,
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

    test('returns a correct partial route to a mid-corridor room', () {
      final path = findPath(
        nodes: testNodes,
        edges: testEdges,
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

    test('returns a single-node path when start equals end', () {
      final path = findPath(
        nodes: testNodes,
        edges: testEdges,
        startNodeId: 'entrance',
        endNodeId: 'entrance',
      );

      expect(path.map((n) => n.id).toList(), ['entrance']);
    });

    test('returns an empty path for an unknown node id', () {
      final path = findPath(
        nodes: testNodes,
        edges: testEdges,
        startNodeId: 'entrance',
        endNodeId: 'does-not-exist',
      );

      expect(path, isEmpty);
    });
  });
}
