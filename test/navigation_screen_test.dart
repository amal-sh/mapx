import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';
import 'package:mapx/screens/navigation_screen.dart';

void main() {
  group('NavigationScreen AR & Bezier Guidance Tests', () {
    late Directory tempDir;
    late File tempFile;
    late LocalMapRepository repo;

    const building = Building(
      id: 'cusat-it',
      name: 'CUSAT IT Block',
      entryFloorId: 'floor-0',
    );
    const floor = Floor(
      id: 'floor-0',
      buildingId: 'cusat-it',
      level: 0,
      name: 'Ground Floor',
    );

    const entrance = MapNode(
      id: 'entrance',
      floorId: 'floor-0',
      type: NodeType.junction,
      label: 'Main Entrance',
      position: Position(x: 0, y: 0, z: 0),
    );
    const junction = MapNode(
      id: 'junction_1',
      floorId: 'floor-0',
      type: NodeType.junction,
      label: 'Corridor Junction',
      position: Position(x: 0, y: 0, z: 8),
    );
    const room101 = MapNode(
      id: 'room_101',
      floorId: 'floor-0',
      type: NodeType.room,
      label: 'Room 101',
      position: Position(x: 6, y: 0, z: 8),
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nav_screen_test_');
      tempFile = File('${tempDir.path}/nav_test.json');
      repo = LocalMapRepository(storageFile: tempFile);

      await repo.saveBuilding(building);
      await repo.saveFloor(floor);
      await repo.saveNode(entrance);
      await repo.saveNode(junction);
      await repo.saveNode(room101);

      await repo.saveEdge(
        const MapEdge(
          id: 'e1',
          fromNodeId: 'entrance',
          toNodeId: 'junction_1',
          floorId: 'floor-0',
          weight: 8.0,
          type: EdgeType.walkable,
        ),
      );
      await repo.saveEdge(
        const MapEdge(
          id: 'e2',
          fromNodeId: 'junction_1',
          toNodeId: 'room_101',
          floorId: 'floor-0',
          weight: 6.0,
          type: EdgeType.walkable,
        ),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('loads path, smooths with Bezier curves, and renders Turn-by-Turn HUD', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            floor: floor,
            destination: room101,
          ),
        ),
      );

      // Settle async loading of graph and pathfinder
      await tester.pumpAndSettle();

      // 1. Check HUD shows start instruction
      expect(find.textContaining('Start from Main Entrance'), findsOneWidget);

      // 2. Check total distance and destination label are rendered in HUD
      expect(find.textContaining('Room 101'), findsWidgets);
      expect(find.textContaining('Total:'), findsOneWidget);

      // 3. Check tracking status pill is rendered
      expect(find.textContaining('Depth Occlusion ON'), findsOneWidget);

      // 4. Check bottom route info is present
      expect(find.text('Route to Room 101'), findsOneWidget);
      expect(find.textContaining('3 waypoints'), findsOneWidget);

      // 5. Advance instruction step via HUD button
      final nextStepBtn = find.byTooltip('Next Step');
      expect(nextStepBtn, findsOneWidget);
      await tester.tap(nextStepBtn);
      await tester.pumpAndSettle();

      // Now should show turn instruction at Junction
      expect(find.textContaining('Turn Right at Corridor Junction'), findsOneWidget);

      // Advance again to Arrival
      await tester.tap(nextStepBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Arrive at Room 101'), findsOneWidget);
    });

    testWidgets('toggles between 3D AR guidance view and 2D floor radar overview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            floor: floor,
            destination: room101,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Check Mini-Map Radar badge is present in AR mode
      expect(find.text('2D'), findsOneWidget);

      // 2. Toggle to full 2D Floor Map via top bar button
      final toggleBtn = find.byTooltip('Switch to 2D Floor Map');
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      // In 2D mode, tooltip should change to Switch to AR View
      expect(find.byTooltip('Switch to AR View'), findsOneWidget);

      // 3. Toggle back to AR View
      await tester.tap(find.byTooltip('Switch to AR View'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Switch to 2D Floor Map'), findsOneWidget);
    });

    testWidgets('simulates movement and dynamically decreases remaining distance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            floor: floor,
            destination: room101,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially at start: Total is 14.0m to Room 101
      expect(find.textContaining('Total: 14.0m to Room 101'), findsOneWidget);

      // Trigger walk simulation button in top bar
      final simulateBtn = find.byTooltip('Simulate Walk');
      expect(simulateBtn, findsOneWidget);
      await tester.tap(simulateBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // After stepping forward, total 14.0m has decreased
      expect(find.textContaining('Total: 14.0m to Room 101'), findsNothing);

      // Stop simulation
      await tester.tap(find.byTooltip('Pause Walk'));
      await tester.pump();
    });
  });
}
