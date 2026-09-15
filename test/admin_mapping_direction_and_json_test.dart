import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/models/node.dart';
import 'package:mapx/native/ar_bridge.dart';
import 'package:mapx/screens/admin_mapping_screen.dart';
import 'package:mapx/widgets/mapping/map_json_viewer_dialog.dart';

void main() {
  group('Admin Mapping Direction & JSON Viewer Tests', () {
    late Directory tempDir;
    late File tempFile;
    late LocalMapRepository repo;

    const building = Building(
      id: 'bldg_test',
      name: 'Test Tech Block',
      entryFloorId: 'floor_test_0',
    );
    const floor = Floor(
      id: 'floor_test_0',
      buildingId: 'bldg_test',
      level: 0,
      name: 'Ground Floor',
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('admin_map_test_');
      tempFile = File('${tempDir.path}/test_map.json');
      repo = LocalMapRepository(storageFile: tempFile);
      await repo.saveBuilding(building);
      await repo.saveFloor(floor);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('Dropping node saves heading and connecting edge stores physical footpath', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminMappingScreen(
                        building: building,
                        floor: floor,
                        repository: repo,
                      ),
                    ),
                  );
                },
                child: const Text('Launch Admin Mapping'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Launch Admin Mapping'));
      await tester.pumpAndSettle();

      // Drop first node (Entrance) at feet
      final dropAtFeet = find.text('Drop at Feet');
      expect(dropAtFeet, findsOneWidget);
      await tester.tap(dropAtFeet);
      await tester.pumpAndSettle();

      // Confirm dialog
      final confirmBtn = find.text('Confirm & Drop Node');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      // Simulate physical walking movement (poses) between node 1 and node 2
      ArBridge.instance.injectEvent(UserPoseEvent(x: 0.0, y: 0.0, z: 0.8));
      await tester.pump(const Duration(milliseconds: 100));
      ArBridge.instance.injectEvent(UserPoseEvent(x: 0.0, y: 0.0, z: 1.6));
      await tester.pump(const Duration(milliseconds: 100));

      // Drop second node (Target 2.0m ahead)
      final dropAtTarget = find.textContaining('Drop at Target');
      expect(dropAtTarget, findsOneWidget);
      await tester.tap(dropAtTarget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm & Drop Node'));
      await tester.pumpAndSettle();

      // Verify 2 nodes were placed
      expect(find.text('2'), findsWidgets);

      // Tap Save button to persist to repository
      final saveBtn = find.widgetWithText(FilledButton, 'Save');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pump();
      // Pump async file I/O operations until AdminMappingScreen completes saving and pops
      for (int i = 0; i < 30; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(AdminMappingScreen).evaluate().isEmpty) break;
      }

      // Verify repository nodes have headings
      final savedNodes = await repo.getNodes(floor.id);
      expect(savedNodes.length, 2);
      expect(savedNodes[0].heading, isNotNull);
      expect(savedNodes[1].heading, isNotNull);

      // Verify repository floor has initialHeadingRadians
      final savedFloor = await repo.getFloor(floor.id);
      expect(savedFloor?.initialHeadingRadians, isNotNull);
      expect(savedFloor?.originAnchor, isNotNull);

      // Verify connecting edge has physical footpath points
      final savedEdges = await repo.getEdges(floor.id);
      expect(savedEdges.length, 1);
      expect(savedEdges.first.footpath, isNotNull);
      expect(savedEdges.first.footpath!.isNotEmpty, isTrue);
    });

    testWidgets('Opening View Map JSON from PopupMenu displays MapJsonViewerDialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminMappingScreen(
            building: building,
            floor: floor,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open PopupMenu
      final menuBtn = find.byTooltip('Floor options');
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Tap View Map JSON
      final viewJsonItem = find.text('View Map JSON');
      expect(viewJsonItem, findsOneWidget);
      await tester.tap(viewJsonItem);
      await tester.pumpAndSettle();

      // Verify MapJsonViewerDialog is displayed
      expect(find.byType(MapJsonViewerDialog), findsOneWidget);
      expect(find.text('Copy JSON'), findsOneWidget);

      // Tap Close button
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(MapJsonViewerDialog), findsNothing);
    });
  });
}
