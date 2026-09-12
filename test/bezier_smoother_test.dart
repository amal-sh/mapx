import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/logic/bezier_smoother.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('BezierSmoother Logic Tests', () {
    test('handles empty and single-node paths gracefully', () {
      expect(BezierSmoother.smoothPath([]), isEmpty);
      expect(BezierSmoother.extractTurnInstructions([]), isEmpty);

      const singleNode = MapNode(
        id: 'start',
        floorId: 'floor-0',
        type: NodeType.junction,
        label: 'Entrance',
        position: Position(x: 1, y: 0, z: 2),
      );

      final singleSmoothed = BezierSmoother.smoothPath([singleNode]);
      expect(singleSmoothed.length, 1);
      expect(singleSmoothed.first.position.x, 1);
      expect(singleSmoothed.first.position.y, 0.75); // Eye-level default offset
      expect(singleSmoothed.first.position.z, 2);
      expect(singleSmoothed.first.isKeyWaypoint, isTrue);

      final singleInstructions = BezierSmoother.extractTurnInstructions([singleNode]);
      expect(singleInstructions.length, 1);
      expect(singleInstructions.first.instruction, contains('Entrance'));
    });

    test('straight corridor segment generates uniformly spaced points with constant heading', () {
      const start = MapNode(
        id: 'n1',
        floorId: 'f0',
        type: NodeType.junction,
        label: 'Start',
        position: Position(x: 0, y: 0, z: 0),
      );
      const end = MapNode(
        id: 'n2',
        floorId: 'f0',
        type: NodeType.room,
        label: 'End',
        position: Position(x: 0, y: 0, z: 6),
      );

      final smoothed = BezierSmoother.smoothPath(
        [start, end],
        stepDistance: 0.75,
        heightOffset: 0.8,
      );

      expect(smoothed.length, greaterThanOrEqualTo(8));
      expect(smoothed.first.position.z, 0.0);
      expect(smoothed.last.position.z, closeTo(6.0, 0.01));

      // All points should have y = 0.8 (eye-level elevation)
      for (final pt in smoothed) {
        expect(pt.position.y, closeTo(0.8, 0.001));
        expect(pt.position.x, closeTo(0.0, 0.001));
      }

      // Distance should increase monotonically to 6.0
      expect(smoothed.last.distanceAlongPath, closeTo(6.0, 0.1));
    });

    test('90-degree corner smooths curvature and maintains wall-safe boundary', () {
      const n1 = MapNode(
        id: 'n1',
        floorId: 'f0',
        type: NodeType.junction,
        label: 'Entrance',
        position: Position(x: 0, y: 0, z: 0),
      );
      const n2 = MapNode(
        id: 'n2',
        floorId: 'f0',
        type: NodeType.junction,
        label: 'Corner',
        position: Position(x: 0, y: 0, z: 5),
      );
      const n3 = MapNode(
        id: 'n3',
        floorId: 'f0',
        type: NodeType.room,
        label: 'Room 101',
        position: Position(x: 5, y: 0, z: 5),
      );

      final smoothed = BezierSmoother.smoothPath(
        [n1, n2, n3],
        stepDistance: 0.5,
        cornerRadius: 1.0,
      );

      expect(smoothed.length, greaterThan(10));
      expect(smoothed.first.position.x, closeTo(0, 0.01));
      expect(smoothed.first.position.z, closeTo(0, 0.01));
      expect(smoothed.last.position.x, closeTo(5, 0.01));
      expect(smoothed.last.position.z, closeTo(5, 0.01));

      // Wall-safety invariant: all points must stay within corridor bounding box [0, 5]
      for (final pt in smoothed) {
        expect(pt.position.x, greaterThanOrEqualTo(-0.01));
        expect(pt.position.x, lessThanOrEqualTo(5.01));
        expect(pt.position.z, greaterThanOrEqualTo(-0.01));
        expect(pt.position.z, lessThanOrEqualTo(5.01));
      }

      // Corner waypoint should be labeled
      final keyWaypoints = smoothed.where((p) => p.isKeyWaypoint);
      expect(keyWaypoints.isNotEmpty, isTrue);
    });

    test('extractTurnInstructions generates correct sequential navigation prompts', () {
      const n1 = MapNode(
        id: 'n1',
        floorId: 'f0',
        type: NodeType.junction,
        label: 'Entrance',
        position: Position(x: 0, y: 0, z: 0),
      );
      const n2 = MapNode(
        id: 'n2',
        floorId: 'f0',
        type: NodeType.junction,
        label: 'Junction North',
        position: Position(x: 0, y: 0, z: 8),
      );
      const n3 = MapNode(
        id: 'n3',
        floorId: 'f0',
        type: NodeType.room,
        label: 'Room 204',
        position: Position(x: 8, y: 0, z: 8),
      );

      final instructions = BezierSmoother.extractTurnInstructions([n1, n2, n3]);

      expect(instructions.length, 3);
      expect(instructions[0].instruction, contains('Start from Entrance'));
      expect(instructions[1].instruction, contains('Turn Right'));
      expect(instructions[2].instruction, contains('Arrive at Room 204'));
      expect(instructions[2].distanceToTurn, closeTo(16.0, 0.01));
    });
  });
}
