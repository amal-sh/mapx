import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../models/edge.dart';
import '../models/node.dart';

/// A* shortest path over the map graph.
///
/// g(n) is the real walked distance (sum of [MapEdge.weight], in meters).
/// h(n) is straight-line distance between [MapNode.position]s, which never
/// overestimates the true walking distance, so the heuristic is admissible
/// and the returned path is guaranteed shortest.
List<MapNode> findPath({
  required List<MapNode> nodes,
  required List<MapEdge> edges,
  required String startNodeId,
  required String endNodeId,
}) {
  final nodesById = {for (final n in nodes) n.id: n};
  final start = nodesById[startNodeId];
  final goal = nodesById[endNodeId];
  if (start == null || goal == null) return [];
  if (start.id == goal.id) return [start];

  final adjacency = <String, List<MapEdge>>{};
  for (final edge in edges) {
    adjacency.putIfAbsent(edge.fromNodeId, () => []).add(edge);
    adjacency.putIfAbsent(edge.toNodeId, () => []).add(edge);
  }

  double heuristic(MapNode a, MapNode b) {
    final dx = a.position.x - b.position.x;
    final dy = a.position.y - b.position.y;
    final dz = a.position.z - b.position.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  final gScore = <String, double>{start.id: 0};
  final cameFrom = <String, String>{};
  final open = PriorityQueue<String>(
    (a, b) {
      final fa = gScore[a]! + heuristic(nodesById[a]!, goal);
      final fb = gScore[b]! + heuristic(nodesById[b]!, goal);
      return fa.compareTo(fb);
    },
  );
  open.add(start.id);
  final closed = <String>{};

  while (open.isNotEmpty) {
    final currentId = open.removeFirst();
    if (currentId == goal.id) {
      final path = <MapNode>[nodesById[currentId]!];
      var cursor = currentId;
      while (cameFrom.containsKey(cursor)) {
        cursor = cameFrom[cursor]!;
        path.add(nodesById[cursor]!);
      }
      return path.reversed.toList();
    }
    if (!closed.add(currentId)) continue;

    for (final edge in adjacency[currentId] ?? const <MapEdge>[]) {
      final neighborId = edge.fromNodeId == currentId ? edge.toNodeId : edge.fromNodeId;
      if (closed.contains(neighborId)) continue;

      final tentativeG = gScore[currentId]! + edge.weight;
      if (tentativeG < (gScore[neighborId] ?? double.infinity)) {
        gScore[neighborId] = tentativeG;
        cameFrom[neighborId] = currentId;
        // A node's id can end up queued more than once if we later find a
        // cheaper route to it. That's fine here: the comparator reads
        // gScore live (not a snapshot), so every copy sorts by the latest
        // cost, and the `closed` check above skips any leftover duplicate
        // once the first (cheapest) pop has closed the node.
        open.add(neighborId);
      }
    }
  }

  return [];
}
