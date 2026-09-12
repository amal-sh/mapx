import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('Admin Mapping Combined Workflow Logic Tests', () {
    late Directory tempDir;
    late File tempFile;
    late LocalMapRepository repo;

    const testBuilding = Building(
      id: 'it-block',
      name: 'IT Block',
      entryFloorId: 'floor-0',
    );
    const testFloor = Floor(
      id: 'floor-0',
      buildingId: 'it-block',
      level: 0,
      name: 'Ground Floor',
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('admin_map_test_');
      tempFile = File('${tempDir.path}/admin_map.json');
      repo = LocalMapRepository(storageFile: tempFile);
      await repo.saveBuilding(testBuilding);
      await repo.saveFloor(testFloor);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('auto-breadcrumb linking connects sequential nodes with Euclidean distance', () async {
      final nodes = <MapNode>[];
      final edges = <MapEdge>[];

      // Admin drops entrance node
      final entrance = MapNode(
        id: 'node_1',
        floorId: testFloor.id,
        type: NodeType.junction,
        label: 'Entrance',
        position: const Position(x: 0, y: 0, z: 0),
      );
      nodes.add(entrance);

      // Admin walks to Room 101 and drops node with Auto-Link enabled
      final room101 = MapNode(
        id: 'node_2',
        floorId: testFloor.id,
        type: NodeType.room,
        label: '101',
        position: const Position(x: 3, y: 0, z: 4),
      );
      nodes.add(room101);

      // Breadcrumb link calculation
      final distance1 = entrance.position.distanceTo(room101.position);
      expect(distance1, closeTo(5.0, 0.001)); // 3-4-5 right triangle

      final edge1 = MapEdge(
        id: 'edge_1_2',
        fromNodeId: entrance.id,
        toNodeId: room101.id,
        floorId: testFloor.id,
        weight: distance1,
        type: EdgeType.walkable,
      );
      edges.add(edge1);

      // Save to repo
      for (final n in nodes) {
        await repo.saveNode(n);
      }
      for (final e in edges) {
        await repo.saveEdge(e);
      }

      final savedNodes = await repo.getNodes(testFloor.id);
      final savedEdges = await repo.getEdges(testFloor.id);

      expect(savedNodes.length, 2);
      expect(savedEdges.length, 1);
      expect(savedEdges.first.weight, 5.0);
    });

    test('manual cross-corridor link connects arbitrary non-sequential nodes', () async {
      final nodeA = MapNode(
        id: 'node_a',
        floorId: testFloor.id,
        type: NodeType.junction,
        label: 'Junction North',
        position: const Position(x: 0, y: 0, z: 10),
      );
      final nodeB = MapNode(
        id: 'node_b',
        floorId: testFloor.id,
        type: NodeType.junction,
        label: 'Junction South',
        position: const Position(x: 0, y: 0, z: 0),
      );

      await repo.saveNode(nodeA);
      await repo.saveNode(nodeB);

      // Manual edge linking
      final manualEdge = MapEdge(
        id: 'edge_manual_ab',
        fromNodeId: nodeA.id,
        toNodeId: nodeB.id,
        floorId: testFloor.id,
        weight: nodeA.position.distanceTo(nodeB.position),
        type: EdgeType.walkable,
      );
      await repo.saveEdge(manualEdge);

      final edges = await repo.getEdges(testFloor.id);
      expect(edges.length, 1);
      expect(edges.first.weight, 10.0);
      expect(edges.first.fromNodeId, 'node_a');
      expect(edges.first.toNodeId, 'node_b');
    });
  });
}
