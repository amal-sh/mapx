import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/logic/mapping_quality_advisor.dart';
import 'package:mapx/logic/spatial_odometry_tracker.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('SpatialOdometryTracker Tests', () {
    late SpatialOdometryTracker tracker;

    setUp(() {
      tracker = SpatialOdometryTracker(strideLengthMeters: 0.75);
    });

    test('initializes at origin with zero distance and steps', () {
      expect(tracker.currentPosition.x, 0.0);
      expect(tracker.currentPosition.z, 0.0);
      expect(tracker.totalSteps, 0);
      expect(tracker.totalDistanceWalked, 0.0);
      expect(tracker.distanceFromLastNode, 0.0);
    });

    test('recordStep advances position along heading vector (forward Z)', () {
      // Heading 0 = along +Z
      tracker.recordStep();
      expect(tracker.totalSteps, 1);
      expect(tracker.stepsSinceLastNode, 1);
      expect(tracker.totalDistanceWalked, 0.75);
      expect(tracker.currentPosition.x, 0.0);
      expect(tracker.currentPosition.z, closeTo(0.75, 0.01));

      // 4 more steps (total 5 steps = 3.75m)
      for (int i = 0; i < 4; i++) {
        tracker.recordStep();
      }
      expect(tracker.totalSteps, 5);
      expect(tracker.currentPosition.z, closeTo(3.75, 0.01));
      expect(tracker.distanceFromLastNode, closeTo(3.75, 0.01));
    });

    test('recordStep advances position along rotated heading (East / +X)', () {
      // Rotate heading 90 degrees (pi / 2) -> along +X
      tracker.setHeading(math.pi / 2);
      tracker.recordStep();
      expect(tracker.currentPosition.x, closeTo(0.75, 0.01));
      expect(tracker.currentPosition.z, closeTo(0.0, 0.01));
    });

    test('setLastPlacedNode updates anchor and resets stepsSinceLastNode', () {
      final node1 = MapNode(
        id: 'node_1',
        floorId: 'floor_1',
        type: NodeType.junction,
        label: 'Entrance',
        position: const Position(x: 0, y: 0, z: 0),
      );
      tracker.setLastPlacedNode(node1);

      // Walk 10 steps (7.5m)
      for (int i = 0; i < 10; i++) {
        tracker.recordStep();
      }
      expect(tracker.stepsSinceLastNode, 10);
      expect(tracker.distanceFromLastNode, closeTo(7.5, 0.01));

      // Drop node 2 at current position
      final node2 = MapNode(
        id: 'node_2',
        floorId: 'floor_1',
        type: NodeType.room,
        label: 'Room 101',
        position: tracker.currentPosition,
      );
      tracker.setLastPlacedNode(node2);

      // Distance from node 2 is now 0.0m, steps reset
      expect(tracker.stepsSinceLastNode, 0);
      expect(tracker.distanceFromLastNode, closeTo(0.0, 0.01));
    });

    test('manual distance override snaps node position to exact blueprint measurement', () {
      final node1 = MapNode(
        id: 'node_1',
        floorId: 'floor_1',
        type: NodeType.junction,
        label: 'Entrance',
        position: const Position(x: 0, y: 0, z: 0),
      );
      tracker.setLastPlacedNode(node1);

      // User walked approx 6.3m (8 steps @ 0.75m = 6.0m, +1 step = 6.75m)
      for (int i = 0; i < 9; i++) {
        tracker.recordStep();
      }

      // Blueprint is exactly 6.0m
      final blueprintPos = tracker.calculateNodePosition(manualDistanceOverride: 6.0);
      expect(blueprintPos.z, closeTo(6.0, 0.01));
      expect(blueprintPos.x, closeTo(0.0, 0.01));
    });

    test('anti-collision guard flags distance < 0.8m', () {
      final node1 = MapNode(
        id: 'node_1',
        floorId: 'floor_1',
        type: NodeType.junction,
        label: 'Entrance',
        position: const Position(x: 0, y: 0, z: 0),
      );
      tracker.setLastPlacedNode(node1);

      // Without walking, distance is 0.0m
      expect(tracker.isTooCloseToLastNode(), isTrue);

      // 1 step (0.75m < 0.8m)
      tracker.recordStep();
      expect(tracker.isTooCloseToLastNode(), isTrue);

      // 2nd step (1.5m >= 0.8m)
      tracker.recordStep();
      expect(tracker.isTooCloseToLastNode(), isFalse);
    });

    test('loop closure candidate detection finds existing node within 2.5m', () {
      final entrance = MapNode(
        id: 'entrance',
        floorId: 'floor_1',
        type: NodeType.junction,
        label: 'Entrance',
        position: const Position(x: 0, y: 0, z: 0),
      );
      final room1 = MapNode(
        id: 'room_1',
        floorId: 'floor_1',
        type: NodeType.room,
        label: 'Room 101',
        position: const Position(x: 0, y: 0, z: 10),
      );
      final room2 = MapNode(
        id: 'room_2',
        floorId: 'floor_1',
        type: NodeType.room,
        label: 'Room 102',
        position: const Position(x: 5, y: 0, z: 10),
      );
      final nodes = [entrance, room1, room2];

      // Admin walks back near entrance (e.g. at x: 1.0, z: 0.5 -> dist ~1.1m)
      tracker.advanceDistance(1.0);
      tracker.setHeading(math.pi / 2);
      tracker.advanceDistance(0.5);

      final candidate = tracker.checkLoopClosureCandidate(
        nodes,
        thresholdMeters: 2.5,
        excludeNodeId: 'room_2',
      );
      expect(candidate, isNotNull);
      expect(candidate!.id, 'entrance');
    });

    test('breadcrumb trail stores walked trajectory', () {
      for (int i = 0; i < 5; i++) {
        tracker.recordStep();
      }
      expect(tracker.breadcrumbTrail.length, 5);
      expect(tracker.breadcrumbTrail.first.position.z, closeTo(0.75, 0.01));
      expect(tracker.breadcrumbTrail.last.position.z, closeTo(3.75, 0.01));
    });

    test('isRecording gate ignores accidental steps when paused and records when held/active', () {
      // Pause tracking (like when admin is standing still or not holding button)
      tracker.pauseRecording();
      expect(tracker.isRecording, isFalse);

      // Accidental steps while stationary should be ignored
      tracker.recordStep();
      tracker.recordStep();
      tracker.advanceDistance(2.0);
      expect(tracker.totalSteps, 0);
      expect(tracker.totalDistanceWalked, 0.0);
      expect(tracker.currentPosition.z, 0.0);

      // Force flag can override for manual simulator button
      tracker.recordStep(force: true);
      expect(tracker.totalSteps, 1);
      expect(tracker.totalDistanceWalked, 0.75);

      // Admin presses and holds button to walk
      tracker.startRecording();
      expect(tracker.isRecording, isTrue);

      tracker.recordStep();
      tracker.recordStep();
      expect(tracker.totalSteps, 3);
      expect(tracker.totalDistanceWalked, closeTo(2.25, 0.01));

      // Admin releases button at destination
      tracker.pauseRecording();
      expect(tracker.isRecording, isFalse);
      tracker.recordStep(); // Ignored
      expect(tracker.totalSteps, 3);
    });
  });

  group('MappingQualityAdvisor Tests', () {
    late MappingQualityAdvisor advisor;

    setUp(() {
      advisor = MappingQualityAdvisor();
    });

    test('emits low-light warning when luminance is below threshold', () {
      advisor.updateCameraMetrics(averageLuminance: 25.0); // very dark
      final alert = advisor.evaluate(
        distanceFromLastNode: 5.0,
        nodeCount: 2,
      );
      expect(alert, isNotNull);
      expect(alert!.type, AlertType.lowLight);
      expect(alert.actionLabel, 'Torch On');
    });

    test('emits walking too fast warning when speed exceeds 1.8 m/s', () {
      advisor.updateCameraMetrics(averageLuminance: 120.0);
      advisor.updateMotionMetrics(speedMps: 2.4); // running / walking fast
      final alert = advisor.evaluate(
        distanceFromLastNode: 5.0,
        nodeCount: 2,
      );
      expect(alert, isNotNull);
      expect(alert!.type, AlertType.walkingTooFast);
    });

    test('emits loop closure suggestion when near existing node', () {
      advisor.updateCameraMetrics(averageLuminance: 120.0);
      advisor.updateMotionMetrics(speedMps: 0.8);
      final loopNode = MapNode(
        id: 'entrance',
        floorId: 'floor_1',
        type: NodeType.junction,
        label: 'Entrance',
        position: const Position(x: 0, y: 0, z: 0),
      );

      final alert = advisor.evaluate(
        distanceFromLastNode: 8.0,
        nodeCount: 4,
        loopCandidate: loopNode,
        loopCandidateDistance: 1.5,
      );
      expect(alert, isNotNull);
      expect(alert!.type, AlertType.loopClosureAvailable);
      expect(alert.actionLabel, 'Link Loop');
      expect(alert.targetNode?.id, 'entrance');
    });

    test('emits too close alert when distance from last node is < 0.8m', () {
      advisor.updateCameraMetrics(averageLuminance: 120.0);
      advisor.updateMotionMetrics(speedMps: 0.0);
      final alert = advisor.evaluate(
        distanceFromLastNode: 0.3,
        nodeCount: 2,
      );
      expect(alert, isNotNull);
      expect(alert!.type, AlertType.tooCloseToNode);
    });

    test('emits bad tilt alert when phone is pointed up at ceiling', () {
      advisor.updateCameraMetrics(averageLuminance: 120.0);
      advisor.updateMotionMetrics(speedMps: 0.5, pitchDeg: 85.0);
      final alert = advisor.evaluate(
        distanceFromLastNode: 3.0,
        nodeCount: 2,
      );
      expect(alert, isNotNull);
      expect(alert!.type, AlertType.badTilt);
    });
  });
}
