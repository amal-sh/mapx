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

class TrackingStateChangedEvent extends ArEvent {
  final TrackingState state;

  TrackingStateChangedEvent(this.state);
}

/// Dart-side wrapper for the `mapx/ar_bridge` Method Channel and
/// `mapx/ar_events` Event Channel (native side: android/.../ArBridge.kt).
///
/// Native handlers are stubs until Phases 2/4/7 fill them in with real
/// ARCore/SceneView/MLKit calls — this class is the seam the rest of the
/// app builds against so screens don't change when they do.
class ArBridge {
  ArBridge._();

  static final ArBridge instance = ArBridge._();

  static const MethodChannel _methodChannel = MethodChannel('mapx/ar_bridge');
  static const EventChannel _eventChannel = EventChannel('mapx/ar_events');

  Stream<ArEvent>? _events;

  Future<bool> startArSession(String floorId) async {
    final result = await _methodChannel.invokeMethod<bool>('startArSession', {
      'floorId': floorId,
    });
    return result ?? false;
  }

  Future<void> renderPath(List<Vector3> points) {
    return _methodChannel.invokeMethod('renderPath', {
      'points': points.map((p) => p.toMap()).toList(),
    });
  }

  Future<void> stopArSession() {
    return _methodChannel.invokeMethod('stopArSession');
  }

  /// Broadcast stream of native AR events. Safe to listen to even when no
  /// native implementation is registered (e.g. running on web/desktop during
  /// UI development) — errors are swallowed rather than thrown.
  Stream<ArEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map(_parseEvent)
        .handleError((Object _) {});
  }

  ArEvent _parseEvent(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    switch (map['type']) {
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
      case 'trackingStateChanged':
        return TrackingStateChangedEvent(
          TrackingState.values.byName(map['state'] as String),
        );
      default:
        throw ArgumentError('Unknown AR event type: ${map['type']}');
    }
  }
}
