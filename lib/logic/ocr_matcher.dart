import 'dart:math' as math;
import '../models/node.dart';

/// Result of matching OCR extracted text against a set of candidate [MapNode]s.
class OcrMatchResult {
  final MapNode node;
  final double confidence; // 0.0 to 1.0
  final String matchedText;
  final String rawOcrText;

  const OcrMatchResult({
    required this.node,
    required this.confidence,
    required this.matchedText,
    required this.rawOcrText,
  });

  @override
  String toString() =>
      'OcrMatchResult(node: ${node.label}, confidence: ${confidence.toStringAsFixed(2)}, raw: "$rawOcrText")';
}

/// Intelligent fuzzy matching engine for indoor room doorplates, labels, and signs.
/// Normalizes strings, handles abbreviations (e.g. "RM 101" -> "Room 101"),
/// extracts numerical identifiers, and computes Levenshtein & token similarity.
class OcrMatcher {
  const OcrMatcher._();

  static const Map<String, String> _abbreviations = {
    'rm': 'room',
    'lab': 'laboratory',
    'dept': 'department',
    'hod': 'head of department',
    'sr': 'seminar room',
    'cr': 'class room',
    'conf': 'conference',
    'lh': 'lecture hall',
  };

  /// Normalizes a string: lowercases, expands common abbreviations, and trims whitespace.
  static String normalize(String text) {
    if (text.isEmpty) return '';
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final tokens = cleaned.split(' ').map((t) => _abbreviations[t] ?? t).toList();
    return tokens.join(' ');
  }

  /// Extracts numeric tokens (e.g. "101", "3", "204B" -> ["101"]).
  static List<String> extractNumbers(String text) {
    final matches = RegExp(r'\b\d+[a-z]?\b', caseSensitive: false).allMatches(text);
    return matches.map((m) => m.group(0)!.toLowerCase()).toList();
  }

  /// Computes Levenshtein Distance between two strings.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = math.min(
          v1[j] + 1,
          math.min(v0[j + 1] + 1, v0[j] + cost),
        );
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[s2.length];
  }

  /// Computes similarity score between 0.0 (completely distinct) and 1.0 (identical).
  static double similarity(String s1, String s2) {
    final n1 = normalize(s1);
    final n2 = normalize(s2);
    if (n1.isEmpty && n2.isEmpty) return 1.0;
    if (n1.isEmpty || n2.isEmpty) return 0.0;
    if (n1 == n2) return 1.0;

    // Direct containment bonus
    if (n1.contains(n2) || n2.contains(n1)) {
      final minLen = math.min(n1.length, n2.length);
      final maxLen = math.max(n1.length, n2.length);
      final containmentScore = (minLen / maxLen) * 0.95;
      return math.max(containmentScore, 0.75);
    }

    final maxLen = math.max(n1.length, n2.length);
    final dist = levenshteinDistance(n1, n2);
    return math.max(0.0, 1.0 - (dist / maxLen));
  }

  /// Evaluates match confidence between [rawOcrText] and a single [node].
  static double calculateConfidence(String rawOcrText, MapNode node) {
    final normOcr = normalize(rawOcrText);
    final normLabel = normalize(node.label);

    if (normOcr.isEmpty || normLabel.isEmpty) return 0.0;
    if (normOcr == normLabel) return 1.0;

    // 1. Check numeric identifier alignment (e.g. OCR: "102" or "RM 102", Node: "Room 102")
    final ocrNumbers = extractNumbers(rawOcrText);
    final labelNumbers = extractNumbers(node.label);

    if (ocrNumbers.isNotEmpty && labelNumbers.isNotEmpty) {
      final hasCommonNumber = ocrNumbers.any((n) => labelNumbers.contains(n));
      if (hasCommonNumber) {
        // Numbers match! Check context tokens
        final ocrWords = normOcr.split(' ');
        final labelWords = normLabel.split(' ');
        final commonWords = ocrWords.where((w) => labelWords.contains(w)).length;

        // If numbers match and text has contextual word (e.g. room/lab), 0.95 confidence
        if (commonWords > 0) return 0.95;
        // Even if only the room number matched directly (e.g. "101" vs "Room 101"), 0.88 confidence
        return 0.88;
      }
    }

    // 2. Token overlap similarity (Jaccard)
    final ocrTokens = normOcr.split(' ').toSet();
    final labelTokens = normLabel.split(' ').toSet();
    final intersection = ocrTokens.intersection(labelTokens).length;
    final union = ocrTokens.union(labelTokens).length;
    final jaccard = union > 0 ? intersection / union : 0.0;

    // 3. String similarity
    final strSim = similarity(normOcr, normLabel);

    return math.max(jaccard * 0.9, strSim);
  }

  /// Finds the best matching node from [candidates] given [recognizedText].
  /// Returns `null` if no candidate meets the [threshold] (default: 0.65).
  static OcrMatchResult? findBestMatch(
    String recognizedText,
    List<MapNode> candidates, {
    double threshold = 0.65,
  }) {
    if (recognizedText.trim().isEmpty || candidates.isEmpty) return null;

    MapNode? bestNode;
    double bestConfidence = 0.0;

    for (final node in candidates) {
      final conf = calculateConfidence(recognizedText, node);
      if (conf > bestConfidence) {
        bestConfidence = conf;
        bestNode = node;
      }
    }

    if (bestNode != null && bestConfidence >= threshold) {
      return OcrMatchResult(
        node: bestNode,
        confidence: bestConfidence,
        matchedText: bestNode.label,
        rawOcrText: recognizedText,
      );
    }

    return null;
  }
}
