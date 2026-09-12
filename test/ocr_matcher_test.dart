import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/logic/ocr_matcher.dart';
import 'package:mapx/models/node.dart';

void main() {
  group('OcrMatcher Tests', () {
    final testNodes = [
      const MapNode(
        id: 'node_101',
        floorId: 'floor_1',
        label: 'Room 101',
        type: NodeType.room,
        position: Position(x: 0, y: 0, z: 0),
      ),
      const MapNode(
        id: 'node_102',
        floorId: 'floor_1',
        label: 'Room 102',
        type: NodeType.room,
        position: Position(x: 5, y: 0, z: 0),
      ),
      const MapNode(
        id: 'node_lab3',
        floorId: 'floor_1',
        label: 'Computer Lab 3',
        type: NodeType.room,
        position: Position(x: 10, y: 0, z: 0),
      ),
      const MapNode(
        id: 'node_hod',
        floorId: 'floor_1',
        label: 'HOD Office',
        type: NodeType.room,
        position: Position(x: 15, y: 0, z: 0),
      ),
      const MapNode(
        id: 'node_stairs',
        floorId: 'floor_1',
        label: 'Stairs A',
        type: NodeType.stair,
        position: Position(x: 20, y: 0, z: 0),
      ),
    ];

    test('exact match returns confidence 1.0', () {
      final match = OcrMatcher.findBestMatch('Room 101', testNodes);
      expect(match, isNotNull);
      expect(match!.node.id, 'node_101');
      expect(match.confidence, 1.0);
    });

    test('case-insensitive match with extra whitespace', () {
      final match = OcrMatcher.findBestMatch('  rOoM  102  ', testNodes);
      expect(match, isNotNull);
      expect(match!.node.id, 'node_102');
      expect(match.confidence, 1.0);
    });

    test('abbreviation expansion matches RM to Room', () {
      final match = OcrMatcher.findBestMatch('RM 101', testNodes);
      expect(match, isNotNull);
      expect(match!.node.id, 'node_101');
      expect(match.confidence, greaterThanOrEqualTo(0.9));
    });

    test('numeric identifier only matches corresponding room', () {
      final match = OcrMatcher.findBestMatch('101', testNodes);
      expect(match, isNotNull);
      expect(match!.node.id, 'node_101');
      expect(match.confidence, greaterThanOrEqualTo(0.85));
    });

    test('partial / substring matches for Lab and HOD', () {
      final matchLab = OcrMatcher.findBestMatch('Lab 3', testNodes);
      expect(matchLab, isNotNull);
      expect(matchLab!.node.id, 'node_lab3');

      final matchHod = OcrMatcher.findBestMatch('HOD', testNodes);
      expect(matchHod, isNotNull);
      expect(matchHod!.node.id, 'node_hod');
    });

    test('rejects unrelated text below threshold', () {
      final match = OcrMatcher.findBestMatch('FIRE EXTINGUISHER', testNodes);
      expect(match, isNull);

      final match2 = OcrMatcher.findBestMatch('RESTROOM MEN', testNodes);
      expect(match2, isNull);
    });

    test('empty recognized text or empty candidates returns null', () {
      expect(OcrMatcher.findBestMatch('', testNodes), isNull);
      expect(OcrMatcher.findBestMatch('   ', testNodes), isNull);
      expect(OcrMatcher.findBestMatch('Room 101', []), isNull);
    });
  });
}
