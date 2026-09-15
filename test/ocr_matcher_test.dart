import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/logic/ocr_matcher.dart';
import 'package:mapx/models/edge.dart';
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

    test('getContextConstrainedCandidates prunes candidates to 1-hop neighborhood', () {
      final edges = [
        const MapEdge(
          id: 'e1',
          fromNodeId: 'node_101',
          toNodeId: 'node_102',
          floorId: 'floor_1',
          weight: 5.0,
          type: EdgeType.walkable,
        ),
        const MapEdge(
          id: 'e2',
          fromNodeId: 'node_102',
          toNodeId: 'node_lab3',
          floorId: 'floor_1',
          weight: 5.0,
          type: EdgeType.walkable,
        ),
        const MapEdge(
          id: 'e3',
          fromNodeId: 'node_lab3',
          toNodeId: 'node_hod',
          floorId: 'floor_1',
          weight: 5.0,
          type: EdgeType.walkable,
        ),
      ];

      // Active node is node_101. 1-hop neighbor should be node_102, but NOT node_lab3 or node_hod
      final candidates = OcrMatcher.getContextConstrainedCandidates(
        activeNodes: [testNodes[0]], // node_101
        allNodes: testNodes,
        allEdges: edges,
        hopRadius: 1,
      );

      final candidateIds = candidates.map((n) => n.id).toSet();
      expect(candidateIds, contains('node_101'));
      expect(candidateIds, contains('node_102'));
      expect(candidateIds.contains('node_lab3'), isFalse);
      expect(candidateIds.contains('node_hod'), isFalse);

      // If activeNodes is empty, falls back to all nodes
      final fallback = OcrMatcher.getContextConstrainedCandidates(
        activeNodes: [],
        allNodes: testNodes,
        allEdges: edges,
      );
      expect(fallback.length, testNodes.length);
    });

    group('TemporalOcrVotingBuffer Tests', () {
      test('instant threshold triggers immediately without accumulating votes', () {
        final buffer = TemporalOcrVotingBuffer(
          requiredVotes: 2,
          instantConfidenceThreshold: 0.90,
        );

        final triggered = buffer.recordVote('node_101', 0.95);
        expect(triggered, isTrue);
      });

      test('sub-threshold vote requires requiredVotes within window', () {
        final buffer = TemporalOcrVotingBuffer(
          requiredVotes: 2,
          windowDuration: const Duration(milliseconds: 1000),
          instantConfidenceThreshold: 0.90,
        );

        final t0 = DateTime(2026, 1, 1, 12, 0, 0);
        // Vote 1 (confidence 0.75): should not trigger yet
        expect(buffer.recordVote('node_101', 0.75, timestamp: t0), isFalse);
        expect(buffer.getVoteCount('node_101', timestamp: t0), 1);

        // Vote 2 (confidence 0.78, 200ms later): should trigger!
        final t1 = t0.add(const Duration(milliseconds: 200));
        expect(buffer.recordVote('node_101', 0.78, timestamp: t1), isTrue);

        // Buffer for node_101 should be cleared after trigger
        expect(buffer.getVoteCount('node_101', timestamp: t1), 0);
      });

      test('stale votes outside window are pruned and do not accumulate', () {
        final buffer = TemporalOcrVotingBuffer(
          requiredVotes: 2,
          windowDuration: const Duration(milliseconds: 1000),
          instantConfidenceThreshold: 0.90,
        );

        final t0 = DateTime(2026, 1, 1, 12, 0, 0);
        // Vote 1 at t0
        expect(buffer.recordVote('node_101', 0.75, timestamp: t0), isFalse);

        // Vote 2 at t0 + 2000ms (window has expired)
        final t2 = t0.add(const Duration(milliseconds: 2000));
        expect(buffer.recordVote('node_101', 0.75, timestamp: t2), isFalse);
        // Count should only be 1 now, not 2
        expect(buffer.getVoteCount('node_101', timestamp: t2), 1);
      });
    });
  });
}
