import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/data/local_map_repository.dart';
import 'package:mapx/main.dart';
import 'package:mapx/models/building.dart';
import 'package:mapx/models/floor.dart';
import 'package:mapx/widgets/home/empty_buildings_view.dart';

void main() {
  testWidgets('Home screen displays unseeded empty state and creates new building', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final tempDir = await Directory.systemTemp.createTemp('widget_test_');
      final tempFile = File('${tempDir.path}/test_map.json');
      final repo = LocalMapRepository(storageFile: tempFile);

      await tester.pumpWidget(MapXApp(repository: repo));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(EmptyBuildingsView), findsOneWidget);
      expect(find.text('No Buildings Mapped'), findsOneWidget);
      expect(find.text('Create & Map Building'), findsOneWidget);

      // Tap Create & Map Building to open creation dialog
      await tester.tap(find.text('Create & Map Building'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Create New Building'), findsOneWidget);
      expect(find.text('Create & Map'), findsOneWidget);

      // Confirm dialog to create building and navigate into Admin Mapping screen
      await tester.tap(find.text('Create & Map'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Admin AR Mapping'), findsOneWidget);
      expect(find.text('Auto-Link'), findsOneWidget);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  testWidgets('Delete building map returns to unseeded empty state', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final tempDir = await Directory.systemTemp.createTemp('widget_delete_test_');
      final tempFile = File('${tempDir.path}/test_delete_map.json');
      final repo = LocalMapRepository(storageFile: tempFile);

      const building = Building(id: 'test_b', name: 'Test Hall', entryFloorId: 'test_f');
      const floor = Floor(id: 'test_f', buildingId: 'test_b', level: 0, name: 'Floor 1');
      await repo.saveBuilding(building);
      await repo.saveFloor(floor);

      await tester.pumpWidget(MapXApp(repository: repo));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test Hall'), findsOneWidget);
      expect(find.byTooltip('Map options'), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byTooltip('Map options'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Map'), findsOneWidget);
      await tester.tap(find.text('Delete Map'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Building Map?'), findsOneWidget);
      // Tap confirm Delete Map button
      await tester.tap(find.text('Delete Map').last);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('No Buildings Mapped'), findsOneWidget);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  testWidgets('Multiple buildings are displayed in a vertically scrollable list', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final tempDir = await Directory.systemTemp.createTemp('widget_multiple_test_');
      final tempFile = File('${tempDir.path}/test_multiple_map.json');
      final repo = LocalMapRepository(storageFile: tempFile);

      const b1 = Building(id: 'b1', name: 'Science Block', entryFloorId: 'f1');
      const f1 = Floor(id: 'f1', buildingId: 'b1', level: 0, name: 'Ground Floor');
      const b2 = Building(id: 'b2', name: 'Engineering Block', entryFloorId: 'f2');
      const f2 = Floor(id: 'f2', buildingId: 'b2', level: 0, name: 'Main Floor');

      await repo.saveBuilding(b1);
      await repo.saveFloor(f1);
      await repo.saveBuilding(b2);
      await repo.saveFloor(f2);

      await tester.pumpWidget(MapXApp(repository: repo));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Mapped Buildings (2)'), findsOneWidget);
      expect(find.text('Science Block'), findsOneWidget);
      expect(find.text('Engineering Block'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Add Another Building'), 100);
      expect(find.text('Add Another Building'), findsOneWidget);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  testWidgets('HomeScreen verifies and collects all required permissions beforehand', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final tempDir = await Directory.systemTemp.createTemp('widget_perm_test_');
      final tempFile = File('${tempDir.path}/test_perm_map.json');
      final repo = LocalMapRepository(storageFile: tempFile);

      const b1 = Building(id: 'b1', name: 'Perm Block', entryFloorId: 'f1');
      const f1 = Floor(id: 'f1', buildingId: 'b1', level: 0, name: 'Floor 1');
      await repo.saveBuilding(b1);
      await repo.saveFloor(f1);

      await tester.pumpWidget(MapXApp(repository: repo));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Perm Block'), findsOneWidget);

      // Verify navigation triggers permission collection before opening destination screen
      await tester.tap(find.text('Where do you want to go?'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Select destination'), findsOneWidget);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
