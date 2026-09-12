import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';
import 'package:mapx/native/ar_bridge.dart';
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

    testWidgets('allows initializing with custom startNode and calculates direct route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            floor: floor,
            destination: room101,
            startNode: junction,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Route should start from Corridor Junction directly to Room 101
      expect(find.textContaining('Start from Corridor Junction'), findsOneWidget);
      expect(find.textContaining('From: Corridor Junction'), findsWidgets);
      expect(find.textContaining('Total: 6.0m to Room 101'), findsOneWidget);
      expect(find.textContaining('2 waypoints'), findsOneWidget);
    });

    testWidgets('opens start location picker and changes starting location dynamically', (tester) async {
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

      // Initial route from Entrance (total 14.0m)
      expect(find.textContaining('From: Main Entrance'), findsWidgets);
      expect(find.textContaining('Total: 14.0m to Room 101'), findsOneWidget);

      // Tap 'Change' in HUD to open location picker bottom sheet
      final changeBtn = find.text('Change');
      expect(changeBtn, findsOneWidget);
      await tester.tap(changeBtn);
      await tester.pumpAndSettle();

      // Verify bottom sheet opened
      expect(find.text('Select Current Location'), findsOneWidget);
      expect(find.text('Ground Floor • Navigating to Room 101'), findsOneWidget);

      // Select 'Corridor Junction' from the list
      final junctionTile = find.widgetWithText(InkWell, 'Corridor Junction');
      expect(junctionTile, findsOneWidget);
      await tester.tap(junctionTile);
      await tester.pumpAndSettle();

      // Bottom sheet closed and route recomputed from Corridor Junction
      expect(find.text('Select Current Location'), findsNothing);
      expect(find.textContaining('From: Corridor Junction'), findsWidgets);
      expect(find.textContaining('Total: 6.0m to Room 101'), findsOneWidget);
    });

    testWidgets('opens OCR scanner overlay from top bar and sets start location on match', (tester) async {
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

      // Open OCR door scanner from top bar button
      final scanBtn = find.byTooltip('Scan Doorplate (OCR)');
      expect(scanBtn, findsOneWidget);
      await tester.tap(scanBtn);
      await tester.pumpAndSettle();

      // Verify OCR Scanner HUD is displayed
      expect(find.text('MLKit OCR Doorplate Scanner'), findsOneWidget);
      expect(find.text('Point camera at room number or entrance sign'), findsOneWidget);

      // Simulate OCR match event for 'Corridor Junction'
      ArBridge.instance.injectEvent(
        OcrMatchEvent(
          label: 'Corridor Junction',
          screenX: 0.5,
          screenY: 0.5,
          confidence: 0.95,
        ),
      );
      await tester.pumpAndSettle();

      // Scanner overlay exits automatically and route is recomputed from Corridor Junction
      expect(find.text('MLKit OCR Doorplate Scanner'), findsNothing);
      expect(find.textContaining('From: Corridor Junction'), findsWidgets);
      expect(find.textContaining('Total: 6.0m to Room 101'), findsOneWidget);
    });

    testWidgets('doorway drift correction recalibrates user position when passing doorplate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            floor: floor,
            destination: room101,
            startNode: entrance,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // In active navigation, inject an OCR match for the junction along the corridor
      ArBridge.instance.injectEvent(
        OcrMatchEvent(
          label: 'Corridor Junction',
          screenX: 0.5,
          screenY: 0.5,
          confidence: 0.95,
        ),
      );
      await tester.pumpAndSettle();

      // Verify drift correction notification pill appears
      expect(find.textContaining('Odometry calibrated at Corridor Junction'), findsOneWidget);
    });

    testWidgets('displays celebratory arrival message and modal when reaching destination', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            repository: repo,
            floor: floor,
            destination: room101,
            startNode: junction,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially at junction, total 6.0m
      expect(find.textContaining('Total: 6.0m to Room 101'), findsOneWidget);
      expect(find.text('You Have Reached Your Destination!'), findsNothing);

      // Advance instruction step to reach arrival step
      final nextStepBtn = find.byTooltip('Next Step');
      expect(nextStepBtn, findsOneWidget);
      await tester.tap(nextStepBtn);
      await tester.pumpAndSettle();

      // On final step, button transitions to 'Arrive at Destination'
      final arriveBtn = find.byTooltip('Arrive at Destination');
      expect(arriveBtn, findsOneWidget);
      await tester.tap(arriveBtn);
      await tester.pumpAndSettle();

      // 1. Verify celebratory arrival dialog is presented
      expect(find.text('You Have Reached Your Destination!'), findsOneWidget);
      expect(find.textContaining('You have arrived at Room 101 on Ground Floor.'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('View Map'), findsOneWidget);

      // 2. Verify HUD displays celebratory arrival banner
      expect(find.text('Destination Reached!'), findsOneWidget);
      expect(find.text('You have arrived at Room 101'), findsOneWidget);

      // 3. Tap 'Done' to dismiss dialog
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('You Have Reached Your Destination!'), findsNothing);
    });
  });
}
