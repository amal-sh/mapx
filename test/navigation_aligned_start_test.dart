import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';
import 'package:mapx/screens/navigation_screen.dart';
import 'package:mapx/widgets/navigation/ar_perspective_simulation_view.dart';

void main() {
  group('NavigationScreen Aligned Start & Continuous Arrows Tests', () {
    late Directory tempDir;
    late File tempFile;
    late LocalMapRepository repo;

    const building = Building(
      id: 'bldg_nav_test',
      name: 'Innovation Hub',
      entryFloorId: 'floor_hub_0',
    );
    const floor = Floor(
      id: 'floor_hub_0',
      buildingId: 'bldg_nav_test',
      level: 0,
      name: 'Ground Floor',
      initialHeadingRadians: 1.5708, // Facing East
    );

    const entrance = MapNode(
      id: 'entrance',
      floorId: 'floor_hub_0',
      type: NodeType.junction,
      label: 'Main Entrance',
      position: Position(x: 0, y: 0, z: 0),
      heading: 1.5708, // Admin mapped facing East
    );

    const room200 = MapNode(
      id: 'room_200',
      floorId: 'floor_hub_0',
      type: NodeType.room,
      label: 'Room 200',
      position: Position(x: 6, y: 0, z: 0),
      heading: 1.5708,
    );

    const edge = MapEdge(
      id: 'e_entrance_200',
      fromNodeId: 'entrance',
      toNodeId: 'room_200',
      floorId: 'floor_hub_0',
      weight: 6.0,
      type: EdgeType.walkable,
      footpath: [
        Position(x: 1.0, y: 0.0, z: 0.0),
        Position(x: 2.0, y: 0.0, z: 0.0),
        Position(x: 3.0, y: 0.0, z: 0.0),
        Position(x: 4.0, y: 0.0, z: 0.0),
        Position(x: 5.0, y: 0.0, z: 0.0),
      ],
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nav_align_test_');
      tempFile = File('${tempDir.path}/test_nav.json');
      repo = LocalMapRepository(storageFile: tempFile);

      await repo.saveBuilding(building);
      await repo.saveFloor(floor);
      await repo.saveNode(entrance);
      await repo.saveNode(room200);
      await repo.saveEdge(edge);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('NavigationScreen initializes user position at mapped start and aligns camera heading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            destination: room200,
            floor: floor,
            startNode: entrance,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final arViewFinder = find.byType(ArPerspectiveSimulationView);
      expect(arViewFinder, findsOneWidget);

      final arView = tester.widget<ArPerspectiveSimulationView>(arViewFinder);

      // User position is initialized to startNode.position (x=0, y=0, z=0)
      expect(arView.userPosition, isNotNull);
      expect(arView.userPosition!.x, entrance.position.x);
      expect(arView.userPosition!.z, entrance.position.z);

      // Camera heading is aligned with startNode.heading (1.5708 rad)
      expect(arView.cameraHeadingRadians, isNotNull);
      expect(arView.cameraHeadingRadians!, closeTo(1.5708, 0.05));

      // Smoothed points follow the physical edge footpath
      expect(arView.smoothedPoints.isNotEmpty, isTrue);
      // Path length extends from start to destination (~6m)
      expect(arView.smoothedPoints.last.distanceAlongPath, greaterThan(5.0));
    });
  });
}
