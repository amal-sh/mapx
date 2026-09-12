import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('Model Serialization Tests', () {
    test('Building toJson and fromJson', () {
      const building = Building(
        id: 'b1',
        name: 'Science Block',
        entryFloorId: 'f1',
      );
      final json = building.toJson();
      final restored = Building.fromJson(json);

      expect(restored.id, building.id);
      expect(restored.name, building.name);
      expect(restored.entryFloorId, building.entryFloorId);
    });

    test('Floor toJson and fromJson with originAnchor', () {
      const floor = Floor(
        id: 'f1',
        buildingId: 'b1',
        level: 1,
        name: 'First Floor',
        originAnchor: Position(x: 1.5, y: 2.0, z: 0.5),
      );
      final json = floor.toJson();
      final restored = Floor.fromJson(json);

      expect(restored.id, floor.id);
      expect(restored.buildingId, floor.buildingId);
      expect(restored.level, 1);
      expect(restored.name, 'First Floor');
      expect(restored.originAnchor?.x, 1.5);
      expect(restored.originAnchor?.y, 2.0);
      expect(restored.originAnchor?.z, 0.5);
    });

    test('MapNode and Position distance calculation', () {
      const pos1 = Position(x: 0, y: 0, z: 0);
      const pos2 = Position(x: 3, y: 4, z: 0);
      expect(pos1.distanceTo(pos2), closeTo(5.0, 0.001));

      const node = MapNode(
        id: 'n1',
        floorId: 'f1',
        type: NodeType.room,
        label: '101',
        position: pos2,
      );
      final json = node.toJson();
      final restored = MapNode.fromJson(json);

      expect(restored.id, 'n1');
      expect(restored.floorId, 'f1');
      expect(restored.type, NodeType.room);
      expect(restored.label, '101');
      expect(restored.position.x, 3);
      expect(restored.position.y, 4);
    });

    test('MapEdge toJson and fromJson', () {
      const edge = MapEdge(
        id: 'e1',
        fromNodeId: 'n1',
        toNodeId: 'n2',
        floorId: 'f1',
        weight: 12.5,
        type: EdgeType.walkable,
      );
      final json = edge.toJson();
      final restored = MapEdge.fromJson(json);

      expect(restored.id, 'e1');
      expect(restored.fromNodeId, 'n1');
      expect(restored.toNodeId, 'n2');
      expect(restored.weight, 12.5);
      expect(restored.type, EdgeType.walkable);
    });
  });

  group('LocalMapRepository Tests', () {
    late Directory tempDir;
    late File tempFile;
    late LocalMapRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mapx_test_');
      tempFile = File('${tempDir.path}/test_map.json');
      repo = LocalMapRepository(storageFile: tempFile);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initializes empty when file does not exist', () async {
      final buildings = await repo.getBuildings();
      expect(buildings, isEmpty);

      final floors = await repo.getFloors('cusat-it');
      expect(floors, isEmpty);
    });

    test('saves and retrieves nodes and edges dynamically', () async {
      const node1 = MapNode(
        id: 'room-1',
        floorId: 'it-floor-0',
        type: NodeType.room,
        label: 'Room 1',
        position: Position(x: 0, y: 0),
      );
      const node2 = MapNode(
        id: 'room-2',
        floorId: 'it-floor-0',
        type: NodeType.room,
        label: 'Room 2',
        position: Position(x: 5, y: 0),
      );
      final edge = MapEdge(
        id: 'e1-2',
        fromNodeId: 'room-1',
        toNodeId: 'room-2',
        floorId: 'it-floor-0',
        weight: node1.position.distanceTo(node2.position),
        type: EdgeType.walkable,
      );

      await repo.saveNode(node1);
      await repo.saveNode(node2);
      await repo.saveEdge(edge);

      final nodes = await repo.getNodes('it-floor-0');
      expect(nodes.length, 2);
      expect(nodes.map((n) => n.id), containsAll(['room-1', 'room-2']));

      final edges = await repo.getEdges('it-floor-0');
      expect(edges.length, 1);
      expect(edges.first.weight, 5.0);
    });

    test('deleting a node removes associated edges', () async {
      const node1 = MapNode(
        id: 'a',
        floorId: 'f',
        type: NodeType.junction,
        label: 'A',
        position: Position(x: 0, y: 0),
      );
      const node2 = MapNode(
        id: 'b',
        floorId: 'f',
        type: NodeType.room,
        label: 'B',
        position: Position(x: 1, y: 1),
      );
      const edge = MapEdge(
        id: 'e1',
        fromNodeId: 'a',
        toNodeId: 'b',
        floorId: 'f',
        weight: 1.41,
        type: EdgeType.walkable,
      );

      await repo.saveNode(node1);
      await repo.saveNode(node2);
      await repo.saveEdge(edge);

      await repo.deleteNode('a');

      expect(await repo.getNode('a'), isNull);
      expect(await repo.getNode('b'), isNotNull);
      final edges = await repo.getEdges('f');
      expect(edges, isEmpty);
    });

    test('persists data to disk and reloads across instances', () async {
      const customBuilding = Building(
        id: 'engineering-block',
        name: 'Engineering Block',
        entryFloorId: 'floor-1',
      );
      await repo.saveBuilding(customBuilding);

      // Create a new instance pointing to the same file
      final newRepoInstance = LocalMapRepository(storageFile: tempFile);
      final fetched = await newRepoInstance.getBuilding('engineering-block');

      expect(fetched, isNotNull);
      expect(fetched?.name, 'Engineering Block');
    });

    test('export and import JSON', () async {
      const node = MapNode(
        id: 'test-node',
        floorId: 'it-floor-0',
        type: NodeType.room,
        label: 'Test Room',
        position: Position(x: 10, y: 20),
      );
      await repo.saveNode(node);

      final exportedJson = await repo.exportJson();
      expect(exportedJson, contains('Test Room'));

      // New clean repo
      final anotherFile = File('${tempDir.path}/another_map.json');
      final cleanRepo = LocalMapRepository(storageFile: anotherFile);
      await cleanRepo.importJson(exportedJson);

      final restoredNode = await cleanRepo.getNode('test-node');
      expect(restoredNode, isNotNull);
      expect(restoredNode?.label, 'Test Room');
    });

    test('deleteBuilding cascades to all floors, nodes, and edges', () async {
      const b = Building(id: 'b1', name: 'Building 1', entryFloorId: 'f1');
      const f = Floor(id: 'f1', buildingId: 'b1', level: 0, name: 'Floor 1');
      const n = MapNode(id: 'n1', floorId: 'f1', type: NodeType.room, label: 'R1', position: Position(x: 0, y: 0));
      const e = MapEdge(id: 'e1', fromNodeId: 'n1', toNodeId: 'n2', floorId: 'f1', weight: 1.0, type: EdgeType.walkable);

      await repo.saveBuilding(b);
      await repo.saveFloor(f);
      await repo.saveNode(n);
      await repo.saveEdge(e);

      expect(await repo.getBuilding('b1'), isNotNull);
      expect(await repo.getFloor('f1'), isNotNull);
      expect(await repo.getNode('n1'), isNotNull);
      expect(await repo.getEdges('f1'), isNotEmpty);

      await repo.deleteBuilding('b1');

      expect(await repo.getBuilding('b1'), isNull);
      expect(await repo.getFloor('f1'), isNull);
      expect(await repo.getNode('n1'), isNull);
      expect(await repo.getEdges('f1'), isEmpty);
    });

    test('clearFloorMap removes all nodes and edges for that floor', () async {
      const f = Floor(id: 'f1', buildingId: 'b1', level: 0, name: 'Floor 1', originAnchor: Position(x: 1, y: 1));
      const n1 = MapNode(id: 'n1', floorId: 'f1', type: NodeType.room, label: 'R1', position: Position(x: 0, y: 0));
      const n2 = MapNode(id: 'n2', floorId: 'f1', type: NodeType.room, label: 'R2', position: Position(x: 2, y: 0));
      const e = MapEdge(id: 'e1', fromNodeId: 'n1', toNodeId: 'n2', floorId: 'f1', weight: 2.0, type: EdgeType.walkable);

      await repo.saveFloor(f);
      await repo.saveNode(n1);
      await repo.saveNode(n2);
      await repo.saveEdge(e);

      expect((await repo.getNodes('f1')).length, 2);
      expect((await repo.getEdges('f1')).length, 1);

      await repo.clearFloorMap('f1');

      expect(await repo.getNodes('f1'), isEmpty);
      expect(await repo.getEdges('f1'), isEmpty);
      final updatedFloor = await repo.getFloor('f1');
      expect(updatedFloor?.originAnchor, isNull);
    });
  });
}
