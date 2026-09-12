import 'dart:io';

import 'package:flutter/services.dart';

/// A 3D point in a floor's local coordinate space (meters, y = vertical).
class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, [this.z = 0]);

  factory Vector3.fromMap(Map<dynamic, dynamic> map) => Vector3(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
        (map['z'] as num? ?? 0).toDouble(),
      );

  Map<String, double> toMap() => {'x': x, 'y': y, 'z': z};
}

enum TrackingState { normal, limited, lost }

/// Events streamed from the native layer over `mapx/ar_events`, per the
/// contract in the implementation plan (Sec. 5).
sealed class ArEvent {}

class OcrMatchEvent extends ArEvent {
  final String label;
  final double screenX;
  final double screenY;
  final double confidence;

  OcrMatchEvent({
    required this.label,
    required this.screenX,
    required this.screenY,
    required this.confidence,
  });
}

class HitTestResultEvent extends ArEvent {
  final Vector3 worldPose;

  HitTestResultEvent(this.worldPose);
}

class ApproachingNodeEvent extends ArEvent {
  final String nodeId;
  final double distance;

  ApproachingNodeEvent({required this.nodeId, required this.distance});
}

class PlaneDetectedEvent extends ArEvent {
  final int planeCount;
  PlaneDetectedEvent(this.planeCount);
}

class TrackingStateChangedEvent extends ArEvent {
  final TrackingState state;

  TrackingStateChangedEvent(this.state);
}

class UserPoseEvent extends ArEvent {
  final double x;
  final double y;
  final double z;

  UserPoseEvent({required this.x, required this.y, required this.z});
}

class ObstacleDetectedEvent extends ArEvent {
  final double distance;
  final String description;

  ObstacleDetectedEvent({required this.distance, required this.description});
}

/// Dart-side wrapper for the `mapx/ar_bridge` Method Channel and
/// `mapx/ar_events` Event Channel (native side: android/.../ArBridge.kt).
class ArBridge {
  ArBridge._();

  static final ArBridge instance = ArBridge._();

  static const MethodChannel _methodChannel = MethodChannel('mapx/ar_bridge');
  static const EventChannel _eventChannel = EventChannel('mapx/ar_events');

  Stream<ArEvent>? _events;

  Future<bool> startArSession(String floorId) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      final result = await _methodChannel.invokeMethod<bool>('startArSession', {
        'floorId': floorId,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startMappingSession(String floorId) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      final result = await _methodChannel.invokeMethod<bool>('startMappingSession', {
        'floorId': floorId,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Vector3?> hitTest(double screenX, double screenY) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return Vector3(screenX * 5, 0, screenY * 5);
    }
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>('hitTest', {
        'screenX': screenX,
        'screenY': screenY,
      });
      if (result != null) {
        return Vector3.fromMap(result);
      }
    } catch (_) {}
    return null;
  }

  Future<void> renderPath(List<Vector3> points) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return Future.value();
    return _methodChannel.invokeMethod('renderPath', {
      'points': points.map((p) => p.toMap()).toList(),
    });
  }

  Future<void> renderSmoothedPath(List<Map<String, dynamic>> points) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return Future.value();
    return _methodChannel.invokeMethod('renderPath', {
      'points': points,
    });
  }

  Future<void> clearPath() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return Future.value();
    return _methodChannel.invokeMethod('clearPath').catchError((Object _) {});
  }

  Future<void> stopArSession() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return Future.value();
    return _methodChannel.invokeMethod('stopArSession').catchError((Object _) {});
  }

  Future<void> stopMappingSession() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return Future.value();
    return _methodChannel.invokeMethod('stopMappingSession').catchError((Object _) {});
  }

  /// Broadcast stream of native AR events. Safe to listen to even when no
  /// native implementation is registered (e.g. running on web/desktop during
  /// UI development) — errors are swallowed rather than thrown.
  Stream<ArEvent> get events {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return const Stream.empty();
    }
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map(_parseEvent)
        .handleError((Object _) {});
  }

  ArEvent _parseEvent(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    switch (map['type']) {
      case 'planeDetected':
        return PlaneDetectedEvent((map['planeCount'] as num? ?? 1).toInt());
      case 'ocrMatch':
        final screenPos = Map<String, dynamic>.from(map['screenPos'] as Map);
        return OcrMatchEvent(
          label: map['label'] as String,
          screenX: (screenPos['x'] as num).toDouble(),
          screenY: (screenPos['y'] as num).toDouble(),
          confidence: (map['confidence'] as num).toDouble(),
        );
      case 'hitTestResult':
        return HitTestResultEvent(
          Vector3.fromMap(map['worldPose'] as Map),
        );
      case 'approachingNode':
        return ApproachingNodeEvent(
          nodeId: map['nodeId'] as String,
          distance: (map['distance'] as num).toDouble(),
        );
      case 'userPose':
        return UserPoseEvent(
          x: (map['x'] as num).toDouble(),
          y: (map['y'] as num).toDouble(),
          z: (map['z'] as num).toDouble(),
        );
      case 'obstacleDetected':
        return ObstacleDetectedEvent(
          distance: (map['distance'] as num? ?? 1.0).toDouble(),
          description: map['description'] as String? ?? 'Obstacle ahead',
        );
      case 'trackingStateChanged':
        return TrackingStateChangedEvent(
          TrackingState.values.byName(map['state'] as String),
        );
      default:
        throw ArgumentError('Unknown AR event type: ${map['type']}');
    }
  }
}
