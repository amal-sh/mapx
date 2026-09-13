import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/logic/spatial_odometry_tracker.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';
import 'package:mapx/native/ar_bridge.dart';
import 'package:mapx/screens/admin_mapping_screen.dart';
import 'package:mapx/widgets/mapping/ar_mapping_perspective_painter.dart';
import 'package:mapx/widgets/mapping/mapping_mini_map.dart';
import 'package:mapx/widgets/navigation/ar_perspective_simulation_view.dart';

void main() {
  group('3D AR Mapping Perspective & Placement Tests', () {
    test('ArMappingPerspectivePainter projects nodes and performs hit testing', () {
      final nodes = [
        const MapNode(
          id: 'n1',
          floorId: 'floor-1',
          type: NodeType.junction,
          label: 'Entrance',
          position: Position(x: 0, y: 0, z: 2), // 2m in front
        ),
        const MapNode(
          id: 'n2',
          floorId: 'floor-1',
          type: NodeType.room,
          label: 'Room 101',
          position: Position(x: 0, y: 0, z: -5), // Behind camera
        ),
      ];

      final painter = ArMappingPerspectivePainter(
        nodes: nodes,
        edges: [],
        currentUserPosition: const Position(x: 0, y: 0, z: 0),
        headingRadians: 0.0, // facing +Z
        targetFloorPosition: const Position(x: 0, y: 0, z: 2),
        targetDistanceAhead: 2.0,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 800);

      painter.paint(canvas, size);

      // Node 1 (in front) should have a touch target
      // Center of screen X is 200
      final hitNode = painter.hitTestNode(const Offset(200, 500), size, tolerance: 100.0);
      expect(hitNode?.id, 'n1');

      // Node 2 (behind) should not be hit
      final hitBehind = painter.hitTestNode(const Offset(200, 100), size, tolerance: 20.0);
      expect(hitBehind?.id, isNot('n2'));
    });

    test('node is anchored to world: turns away and vanishes, turns back and reappears', () {
      final nodes = [
        const MapNode(
          id: 'n1',
          floorId: 'floor-1',
          type: NodeType.junction,
          label: 'Entrance',
          position: Position(x: 0, y: 0, z: 2), // 2m in front
        ),
      ];
      const size = Size(400, 800);

      // 1. Facing directly forward (heading = 0): node is visible
      final painterForward = ArMappingPerspectivePainter(
        nodes: nodes,
        edges: const [],
        currentUserPosition: const Position(x: 0, y: 0, z: 0),
        headingRadians: 0.0,
        targetFloorPosition: const Position(x: 0, y: 0, z: 2),
        targetDistanceAhead: 2.0,
      );
      final r1 = PictureRecorder();
      painterForward.paint(Canvas(r1), size);
      expect(painterForward.hitTestNode(const Offset(200, 450), size, tolerance: 100.0)?.id, 'n1');

      // 2. Camera turned 90 degrees right (heading = pi/2): node is to the left and off-screen
      final painterTurned = ArMappingPerspectivePainter(
        nodes: nodes,
        edges: const [],
        currentUserPosition: const Position(x: 0, y: 0, z: 0),
        headingRadians: math.pi / 2,
        targetFloorPosition: const Position(x: 2, y: 0, z: 0),
        targetDistanceAhead: 2.0,
      );
      final r2 = PictureRecorder();
      painterTurned.paint(Canvas(r2), size);
      // Not on screen, touch test should be null
      expect(painterTurned.hitTestNode(const Offset(200, 450), size, tolerance: 100.0), isNull);

      // 3. Camera turned around 180 degrees (heading = pi): node is behind camera
      final painterBehind = ArMappingPerspectivePainter(
        nodes: nodes,
        edges: const [],
        currentUserPosition: const Position(x: 0, y: 0, z: 0),
        headingRadians: math.pi,
        targetFloorPosition: const Position(x: 0, y: 0, z: -2),
        targetDistanceAhead: 2.0,
      );
      final r3 = PictureRecorder();
      painterBehind.paint(Canvas(r3), size);
      expect(painterBehind.hitTestNode(const Offset(200, 450), size, tolerance: 100.0), isNull);
    });

    testWidgets('MappingMiniMap renders radar and opens overview on tap', (tester) async {
      final nodes = [
        const MapNode(
          id: 'n1',
          floorId: 'f1',
          type: NodeType.junction,
          label: 'Entrance',
          position: Position(x: 0, y: 0, z: 0),
        ),
        const MapNode(
          id: 'n2',
          floorId: 'f1',
          type: NodeType.room,
          label: 'Room 101',
          position: Position(x: 5, y: 0, z: 5),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MappingMiniMap(
              nodes: nodes,
              edges: const [],
              currentUserPosition: const Position(x: 0, y: 0, z: 0),
              headingRadians: 0.0,
            ),
          ),
        ),
      );

      expect(find.byType(MappingMiniMap), findsOneWidget);
      expect(find.text('2D'), findsOneWidget);

      // Tap to expand
      await tester.tap(find.byType(MappingMiniMap));
      await tester.pumpAndSettle();

      expect(find.text('2D Floor Map Overview'), findsOneWidget);
      expect(find.text('2 nodes • 0 paths'), findsOneWidget);
    });

    testWidgets('AdminMappingScreen displays 3D perspective AR controls and dual placement buttons', (tester) async {
      await tester.runAsync(() async {
        final tempDir = await Directory.systemTemp.createTemp('admin_screen_test_');
        final tempFile = File('${tempDir.path}/map.json');
        final repo = LocalMapRepository(storageFile: tempFile);

        const building = Building(id: 'bld-1', name: 'Main Hall', entryFloorId: 'f-1');
        const floor = Floor(id: 'f-1', buildingId: 'bld-1', level: 1, name: 'Floor 1');

        await repo.saveBuilding(building);
        await repo.saveFloor(floor);

        await tester.pumpWidget(
          MaterialApp(
            home: AdminMappingScreen(
              repository: repo,
              building: building,
              floor: floor,
            ),
          ),
        );

        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 600));

        // Check Dual Drop Buttons are displayed
        expect(find.textContaining('Drop at Target'), findsOneWidget);
        expect(find.text('Drop at Feet'), findsOneWidget);

        // Check distance chips
        expect(find.text('1.0m'), findsOneWidget);
        expect(find.text('2.5m'), findsOneWidget);

        // Check quick turn controls
        expect(find.byTooltip('Turn Left 90°'), findsOneWidget);
        expect(find.byTooltip('Turn Right 90°'), findsOneWidget);
        expect(find.byTooltip('Turn Around 180°'), findsOneWidget);

        // Tap Turn Right 90°
        await tester.tap(find.byTooltip('Turn Right 90°'));
        await tester.pump(const Duration(milliseconds: 100));

        // Heading should now show 90°
        expect(find.text('90°'), findsOneWidget);

        // Verify step simulation button is removed
        expect(find.textContaining('+0.7m'), findsNothing);

        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
    });

    test('ArMappingPerspectivePainter renders 3D breadcrumb dots along tracked path', () {
      final breadcrumbs = [
        BreadcrumbPoint(position: const Position(x: 0, y: 0, z: 0.5), timestamp: DateTime.now()),
        BreadcrumbPoint(position: const Position(x: 0, y: 0, z: 1.0), timestamp: DateTime.now()),
        BreadcrumbPoint(position: const Position(x: 0, y: 0, z: 1.5), timestamp: DateTime.now()),
      ];

      final painter = ArMappingPerspectivePainter(
        nodes: const [],
        edges: const [],
        currentUserPosition: const Position(x: 0, y: 0, z: 1.5),
        headingRadians: 0.0,
        targetFloorPosition: const Position(x: 0, y: 0, z: 2.0),
        targetDistanceAhead: 2.0,
        breadcrumbs: breadcrumbs,
        animationProgress: 0.5,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 800);

      expect(() => painter.paint(canvas, size), returnsNormally);
    });

    testWidgets('MappingMiniMap renders walked breadcrumbs trail on radar and fullscreen', (tester) async {
      final breadcrumbs = [
        BreadcrumbPoint(position: const Position(x: 0, y: 0, z: 0), timestamp: DateTime.now()),
        BreadcrumbPoint(position: const Position(x: 1, y: 0, z: 2), timestamp: DateTime.now()),
        BreadcrumbPoint(position: const Position(x: 2, y: 0, z: 4), timestamp: DateTime.now()),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MappingMiniMap(
              nodes: const [],
              edges: const [],
              currentUserPosition: const Position(x: 2, y: 0, z: 4),
              headingRadians: 0.0,
              breadcrumbs: breadcrumbs,
            ),
          ),
        ),
      );

      expect(find.byType(MappingMiniMap), findsOneWidget);

      // Open fullscreen 2D floor map
      await tester.tap(find.byType(MappingMiniMap));
      await tester.pumpAndSettle();

      expect(find.text('2D Floor Map Overview'), findsOneWidget);
    });

    test('ArPerspectivePainter renders 3D walked breadcrumbs along tracked route', () {
      const destination = MapNode(
        id: 'dest',
        floorId: 'f1',
        type: NodeType.room,
        label: 'Room 101',
        position: Position(x: 0, y: 0, z: 10),
      );

      final walkedBreadcrumbs = [
        const Position(x: 0, y: 0, z: 1),
        const Position(x: 0, y: 0, z: 2),
        const Position(x: 0, y: 0, z: 3),
      ];

      final painter = ArPerspectivePainter(
        points: const [],
        turnInstructions: const [],
        activeStep: 0,
        animationProgress: 0.7,
        destination: destination,
        userPosition: Vector3(0, 0, 3),
        walkedBreadcrumbs: walkedBreadcrumbs,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 800);

      expect(() => painter.paint(canvas, size), returnsNormally);
    });
  });
}
