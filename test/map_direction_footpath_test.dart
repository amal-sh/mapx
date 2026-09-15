import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/logic/bezier_smoother.dart';
import 'package:mapx/logic/spatial_odometry_tracker.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('Map Direction, Heading & Footpath Tests', () {
    late Directory tempDir;
    late File tempFile;
    late LocalMapRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('map_direction_test_');
      tempFile = File('${tempDir.path}/test_map.json');
      repo = LocalMapRepository(storageFile: tempFile);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('MapNode correctly serializes and deserializes heading orientation', () {
      const node = MapNode(
        id: 'node_1',
        floorId: 'floor_0',
        type: NodeType.room,
        label: 'Lab 101',
        position: Position(x: 2.5, y: 0.0, z: 5.0),
        heading: 1.5708, // ~90° (facing East)
      );

      final jsonMap = node.toJson();
      expect(jsonMap['heading'], closeTo(1.5708, 0.0001));

      final deserialized = MapNode.fromJson(jsonMap);
      expect(deserialized.heading, closeTo(1.5708, 0.0001));
      expect(deserialized.label, 'Lab 101');
      expect(deserialized.position.x, 2.5);
    });

    test('Floor correctly serializes and deserializes initialHeadingRadians', () {
      const floor = Floor(
        id: 'floor_0',
        buildingId: 'bldg_1',
        level: 1,
        name: 'First Floor',
        originAnchor: Position(x: 0, y: 0, z: 0),
        initialHeadingRadians: 0.7854, // ~45° (facing NE)
      );

      final jsonMap = floor.toJson();
      expect(jsonMap['initialHeadingRadians'], closeTo(0.7854, 0.0001));

      final deserialized = Floor.fromJson(jsonMap);
      expect(deserialized.initialHeadingRadians, closeTo(0.7854, 0.0001));
      expect(deserialized.name, 'First Floor');
    });

    test('MapEdge correctly serializes and deserializes physical footpath coordinates', () {
      const p1 = Position(x: 0.0, y: 0.0, z: 1.0);
      const p2 = Position(x: 0.5, y: 0.0, z: 2.0);
      const p3 = Position(x: 1.0, y: 0.0, z: 3.0);

      const edge = MapEdge(
        id: 'edge_1_2',
        fromNodeId: 'node_1',
        toNodeId: 'node_2',
        floorId: 'floor_0',
        weight: 3.5,
        type: EdgeType.walkable,
        footpath: [p1, p2, p3],
      );

      final jsonMap = edge.toJson();
      expect(jsonMap['footpath'], isNotNull);
      expect((jsonMap['footpath'] as List).length, 3);

      final deserialized = MapEdge.fromJson(jsonMap);
      expect(deserialized.footpath, isNotNull);
      expect(deserialized.footpath!.length, 3);
      expect(deserialized.footpath![1].x, 0.5);
      expect(deserialized.footpath![1].z, 2.0);
    });

    test('LocalMapRepository persists and exports heading and footpath in exportJson', () async {
      const building = Building(id: 'b1', name: 'Science Block', entryFloorId: 'f1');
      const floor = Floor(
        id: 'f1',
        buildingId: 'b1',
        level: 0,
        name: 'Ground Floor',
        originAnchor: Position(x: 0, y: 0, z: 0),
        initialHeadingRadians: 0.0, // Facing North
      );
      const nodeA = MapNode(
        id: 'nA',
        floorId: 'f1',
        type: NodeType.junction,
        label: 'Entrance',
        position: Position(x: 0, y: 0, z: 0),
        heading: 0.0,
      );
      const nodeB = MapNode(
        id: 'nB',
        floorId: 'f1',
        type: NodeType.room,
        label: 'Room 201',
        position: Position(x: 4, y: 0, z: 0),
        heading: 1.57,
      );
      const edge = MapEdge(
        id: 'eAB',
        fromNodeId: 'nA',
        toNodeId: 'nB',
        floorId: 'f1',
        weight: 4.0,
        type: EdgeType.walkable,
        footpath: [
          Position(x: 1.0, y: 0.0, z: 0.0),
          Position(x: 2.0, y: 0.0, z: 0.0),
          Position(x: 3.0, y: 0.0, z: 0.0),
        ],
      );

      await repo.saveBuilding(building);
      await repo.saveFloor(floor);
      await repo.saveNode(nodeA);
      await repo.saveNode(nodeB);
      await repo.saveEdge(edge);

      final exported = await repo.exportJson();
      expect(exported, contains('"initialHeadingRadians": 0.0'));
      expect(exported, contains('"heading": 0.0'));
      expect(exported, contains('"heading": 1.57'));
      expect(exported, contains('"footpath"'));

      // Re-read with a fresh repository instance pointing to the same file
      final freshRepo = LocalMapRepository(storageFile: tempFile);
      final readFloor = await freshRepo.getFloor('f1');
      expect(readFloor?.initialHeadingRadians, 0.0);

      final readNodes = await freshRepo.getNodes('f1');
      expect(readNodes.firstWhere((n) => n.id == 'nA').heading, 0.0);
      expect(readNodes.firstWhere((n) => n.id == 'nB').heading, 1.57);

      final readEdges = await freshRepo.getEdges('f1');
      expect(readEdges.first.footpath?.length, 3);
      expect(readEdges.first.footpath?[0].x, 1.0);
    });

    test('SpatialOdometryTracker.consumeTrailSinceLastNode extracts segment and resets marker', () {
      final tracker = SpatialOdometryTracker(strideLengthMeters: 1.0);
      tracker.setHeading(0.0); // Facing +Z

      // Place first node
      tracker.setLastPlacedNode(
        const MapNode(
          id: 'n1',
          floorId: 'f1',
          type: NodeType.junction,
          label: 'Start',
          position: Position(x: 0, y: 0, z: 0),
        ),
      );

      // Walk 3 steps
      tracker.recordStep();
      tracker.recordStep();
      tracker.recordStep();

      // Consume trail between node 1 and proposed node 2
      final trailSegment = tracker.consumeTrailSinceLastNode();
      expect(trailSegment.length, 3);
      expect(trailSegment[0].z, closeTo(1.0, 0.05));
      expect(trailSegment[1].z, closeTo(2.0, 0.05));
      expect(trailSegment[2].z, closeTo(3.0, 0.05));

      // Calling consume again immediately returns empty (consumed)
      expect(tracker.consumeTrailSinceLastNode(), isEmpty);

      // Walk 2 more steps
      tracker.recordStep();
      tracker.recordStep();

      final secondSegment = tracker.consumeTrailSinceLastNode();
      expect(secondSegment.length, 2);
    });

    test('BezierSmoother integrates MapEdge.footpath physical steps into the curve', () {
      const start = MapNode(
        id: 'start',
        floorId: 'f1',
        type: NodeType.junction,
        label: 'Start',
        position: Position(x: 0, y: 0, z: 0),
      );
      const end = MapNode(
        id: 'end',
        floorId: 'f1',
        type: NodeType.room,
        label: 'End',
        position: Position(x: 4, y: 0, z: 4),
      );

      // Admin walked an L-shaped corridor: (0,0) -> (0,4) -> (4,4)
      const edge = MapEdge(
        id: 'e1',
        fromNodeId: 'start',
        toNodeId: 'end',
        floorId: 'f1',
        weight: 8.0,
        type: EdgeType.walkable,
        footpath: [
          Position(x: 0, y: 0, z: 1),
          Position(x: 0, y: 0, z: 2),
          Position(x: 0, y: 0, z: 3),
          Position(x: 0, y: 0, z: 4), // Corner turn
          Position(x: 1, y: 0, z: 4),
          Position(x: 2, y: 0, z: 4),
          Position(x: 3, y: 0, z: 4),
        ],
      );

      final smoothedWithoutEdge = BezierSmoother.smoothPath([start, end]);
      final smoothedWithFootpath = BezierSmoother.smoothPath(
        [start, end],
        edges: [edge],
      );

      // Without intermediate footpath, path is a straight diagonal line
      // Midpoint in straight path would have x ~= 2, z ~= 2
      final straightMid = smoothedWithoutEdge[smoothedWithoutEdge.length ~/ 2].position;
      expect(straightMid.x, closeTo(2.0, 0.6));
      expect(straightMid.z, closeTo(2.0, 0.6));

      // With physical footpath, path follows the L-shape corner around (0, 4)
      // Verify points exist along x ~= 0 with z >= 2.5
      final cornerPoint = smoothedWithFootpath.any(
        (p) => p.position.x < 0.5 && p.position.z > 2.5,
      );
      expect(cornerPoint, isTrue);
    });
  });
}
