import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/edge.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';
import 'package:mapx/native/ar_bridge.dart';
import 'package:mapx/screens/navigation_screen.dart';
import 'package:mapx/widgets/navigation/ar_perspective_simulation_view.dart';
import 'package:mapx/widgets/navigation/floor_map_view.dart';
import 'package:mapx/widgets/navigation/mini_map_radar.dart';

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
    const room102 = MapNode(
      id: 'room_102',
      floorId: 'floor-0',
      type: NodeType.room,
      label: 'Room 102',
      position: Position(x: -6, y: 0, z: 8),
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
      await repo.saveNode(room102);

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
      await repo.saveEdge(
        const MapEdge(
          id: 'e3',
          fromNodeId: 'junction_1',
          toNodeId: 'room_102',
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
      expect(find.text('Select Start Location'), findsOneWidget);
      expect(find.text('Ground Floor • To Room 101'), findsOneWidget);

      // Select 'Corridor Junction' from the list
      final junctionTile = find.widgetWithText(InkWell, 'Corridor Junction');
      expect(junctionTile, findsOneWidget);
      await tester.tap(junctionTile);
      await tester.pumpAndSettle();

      // Bottom sheet closed and route recomputed from Corridor Junction
      expect(find.text('Select Start Location'), findsNothing);
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

    testWidgets('anchors 3D AR navigation elements to physical world with camera rotation and compass HUD', (tester) async {
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

      // 1. Initial compass heading pill is displayed at 0°
      expect(find.text('0°'), findsOneWidget);

      // 2. Drag horizontally on the AR viewport to simulate turning the camera away
      await tester.drag(find.byType(GestureDetector).first, const Offset(300, 0));
      await tester.pumpAndSettle();

      // Heading should now be rotated away from 0°
      expect(find.text('0°'), findsNothing);

      // 3. Tap live compass pill to calibrate current heading as forward (0°)
      await tester.tap(find.textContaining('°'));
      await tester.pumpAndSettle();

      // Heading should be recalibrated back to 0°
      expect(find.text('0°'), findsOneWidget);
    });

    testWidgets('drops and displays breadcrumb dots along the path tracked while walking', (tester) async {
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

      // Initially no breadcrumbs or empty
      var arView = tester.widget<ArPerspectiveSimulationView>(find.byType(ArPerspectiveSimulationView));
      expect(arView.walkedBreadcrumbs?.isEmpty ?? true, isTrue);

      // Simulate footsteps / user pose movement along the corridor
      ArBridge.instance.injectEvent(UserPoseEvent(x: 0.0, y: 0.0, z: 1.0));
      await tester.pumpAndSettle();

      ArBridge.instance.injectEvent(UserPoseEvent(x: 0.0, y: 0.0, z: 2.0));
      await tester.pumpAndSettle();

      ArBridge.instance.injectEvent(UserPoseEvent(x: 0.0, y: 0.0, z: 3.0));
      await tester.pumpAndSettle();

      // Verify breadcrumbs were dropped along the walked path in the 3D AR view
      arView = tester.widget<ArPerspectiveSimulationView>(find.byType(ArPerspectiveSimulationView));
      expect(arView.walkedBreadcrumbs, isNotNull);
      expect(arView.walkedBreadcrumbs!.length, 3);
      expect(arView.walkedBreadcrumbs![0].z, 1.0);
      expect(arView.walkedBreadcrumbs![1].z, 2.0);
      expect(arView.walkedBreadcrumbs![2].z, 3.0);

      // Switch to 2D Floor Map and verify walked breadcrumbs are also present
      final mapToggle = find.byTooltip('Switch to 2D Floor Map');
      expect(mapToggle, findsOneWidget);
      await tester.tap(mapToggle);
      await tester.pumpAndSettle();

      final floorMap = tester.widget<FloorMapView>(find.byType(FloorMapView));
      expect(floorMap.walkedBreadcrumbs, isNotNull);
      expect(floorMap.walkedBreadcrumbs!.length, 3);
    });

    testWidgets('autonomous 1-hop rerouting detects off-route doorplate and recalculates route', (tester) async {
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

      // Initial route: Entrance -> Junction -> Room 101 (14m total)
      expect(find.textContaining('Start from Main Entrance'), findsOneWidget);
      expect(find.textContaining('Total: 14.0m to Room 101'), findsOneWidget);

      // User accidentally turned into the wrong wing and sees Room 102 (a 1-hop neighbor of junction)
      ArBridge.instance.injectEvent(
        OcrMatchEvent(
          label: 'Room 102',
          screenX: 0.5,
          screenY: 0.5,
          confidence: 0.95,
        ),
      );
      await tester.pumpAndSettle();

      // Verify autonomous rerouting notice was triggered
      expect(find.textContaining('Off-route detected: rerouting from Room 102'), findsOneWidget);

      // Route recomputed from Room 102: Room 102 -> Junction -> Room 101 (12.0m total)
      expect(find.textContaining('From: Room 102'), findsWidgets);
      expect(find.textContaining('Total: 12.0m to Room 101'), findsOneWidget);
    });

    testWidgets('toggles adaptive mini-map collapse and expand to minimize cognitive load', (tester) async {
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

      // In default expanded mode, the '2D' fullscreen badge and chevron-down collapse button are present
      expect(find.text('2D'), findsOneWidget);
      final collapseBtn = find.descendant(
        of: find.byType(MiniMapRadar),
        matching: find.byIcon(CupertinoIcons.chevron_down),
      );
      expect(collapseBtn, findsOneWidget);

      // Tap collapse button to minimize mini-map radar
      await tester.tap(collapseBtn);
      await tester.pumpAndSettle();

      // Now mini-map is in compact pill mode with 'Radar' label and expand icon
      expect(find.text('2D'), findsNothing);
      expect(find.textContaining('Radar'), findsOneWidget);
      final expandIcon = find.descendant(
        of: find.byType(MiniMapRadar),
        matching: find.byIcon(CupertinoIcons.chevron_up),
      );
      expect(expandIcon, findsOneWidget);

      // Tap compact pill to expand back
      await tester.tap(expandIcon);
      await tester.pumpAndSettle();

      // Fully expanded again
      expect(find.text('2D'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniMapRadar), matching: find.byIcon(CupertinoIcons.chevron_down)),
        findsOneWidget,
      );
    });
  });
}
