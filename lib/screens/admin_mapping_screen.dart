import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/map_repository.dart';
import '../logic/mapping_quality_advisor.dart';
import '../logic/physical_orientation_tracker.dart';
import '../logic/spatial_odometry_tracker.dart';
import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';
import '../native/ar_bridge.dart';
import '../native/camera_permission.dart';
import '../widgets/mapping/ar_mapping_perspective_painter.dart';
import '../widgets/mapping/mapping_controls_bar.dart';
import '../widgets/mapping/native_ar_scene_view.dart';
import '../widgets/mapping/mapping_inspector_sheet.dart';
import '../widgets/mapping/mapping_mini_map.dart';
import '../widgets/mapping/node_form_dialog.dart';

/// In-app AR Mapping tool for building administrators.
///
/// Features:
/// - Real-time Spatial Odometry & Pedestrian Dead Reckoning (PDR):
///   tracks continuous world position, distance walked, and heading as admin moves.
/// - Environmental & Tracking Quality Advisor:
///   alerts for low light, excessive walking speed, phone tilt, and featureless surfaces.
/// - 1-Tap Flashlight / Torch toggle for low-light corridors.
/// - Auto-Breadcrumb linking: automatically connects nodes with true Euclidean distance.
/// - Loop closure detection: identifies nearby existing nodes when completing hallway loops.
/// - Anti-collision guard & distance fine-tuning steppers.
/// - Pre-save graph health validation checking for orphaned nodes.
class AdminMappingScreen extends StatefulWidget {
  const AdminMappingScreen({
    super.key,
    required this.repository,
    required this.building,
    required this.floor,
  });

  final MapRepository repository;
  final Building building;
  final Floor floor;

  @override
  State<AdminMappingScreen> createState() => _AdminMappingScreenState();
}

class _AdminMappingScreenState extends State<AdminMappingScreen>
    with SingleTickerProviderStateMixin {
  final List<MapNode> _nodes = [];
  final List<MapEdge> _edges = [];

  final SpatialOdometryTracker _odometryTracker = SpatialOdometryTracker();
  final PhysicalOrientationTracker _orientationTracker = PhysicalOrientationTracker();
  final MappingQualityAdvisor _advisor = MappingQualityAdvisor();

  bool _loading = true;
  bool _mappingSessionActive = false;
  bool _breadcrumbMode = true;
  MapNode? _lastPlacedNode;
  MapNode? _linkSourceNode;
  MapNode? _selectedNode;
  bool _isLinkingMode = false;
  // ignore: unused_field
  int _planeCount = 0;
  StreamSubscription<ArEvent>? _arSubscription;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  int? _lastCumulativeStepCount;
  DateTime _lastStepTime = DateTime.now();
  static const double _stepThreshold = 1.35; // m/s^2 user-acceleration spike on footstep impact
  static const int _stepDebounceMs = 320;

  CameraController? _cameraController;
  bool _cameraInitialized = false;
  bool _isTorchOn = false;
  bool _isStreamingImages = false;
  DateTime _lastLumaCheck = DateTime.now();

  AdvisorAlert? _currentAlert;
  Timer? _advisorCheckTimer;

  bool _isTrackingActive = true;

  late final AnimationController _pulseAnimationController;
  double _targetDistanceAhead = 2.0;
  ArMappingPerspectivePainter? _lastPainter;

  Position get _targetFloorPosition => _odometryTracker.calculateNodePosition(
        forwardOffsetMeters: _targetDistanceAhead,
      );

  @override
  void initState() {
    super.initState();
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _pulseAnimationController.repeat();
    }
    _odometryTracker.startRecording(); // Active by default: walk freely!
    _orientationTracker.addListener(_onOrientationChanged);
    _orientationTracker.start();
    _loadExistingGraph();
    _initAr();
    _initSensors();
    _initCamera();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _advisorCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _updateAdvisorAlert();
      });
    }
  }

  void _onOrientationChanged() {
    if (!mounted) return;
    setState(() {
      _odometryTracker.setHeading(_orientationTracker.headingRadians);
      _updateAdvisorAlert();
    });
  }

  void _calibrateForward() {
    _orientationTracker.calibrateCurrentAsForward();
    _odometryTracker.setHeading(_orientationTracker.headingRadians);
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🧭 Forward heading calibrated to current camera view!'),
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  void dispose() {
    _advisorCheckTimer?.cancel();
    _orientationTracker.removeListener(_onOrientationChanged);
    _orientationTracker.stop();
    _pulseAnimationController.dispose();
    _accelSubscription?.cancel();
    _stepCountSubscription?.cancel();
    _arSubscription?.cancel();
    if (_isStreamingImages && _cameraController != null) {
      _cameraController!.stopImageStream().catchError((Object _) {});
    }
    _cameraController?.dispose();
    ArBridge.instance.stopMappingSession();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    // On Android devices, SceneView ARSceneView exclusively manages camera hardware.
    if (Platform.isAndroid) return;
    final granted = await ensureCameraPermission();
    if (!granted) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (mounted) {
        setState(() {
          _cameraController = controller;
          _cameraInitialized = true;
        });

        // Start throttled camera frame luminance stream for low-light detection
        try {
          await controller.startImageStream(_processCameraFrame);
          _isStreamingImages = true;
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _processCameraFrame(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastLumaCheck).inMilliseconds < 400) return;
    _lastLumaCheck = now;

    if (image.planes.isNotEmpty) {
      final bytes = image.planes[0].bytes;
      int total = 0;
      int count = 0;
      // Sample every 128th pixel for lightweight computation (<0.1ms)
      for (int i = 0; i < bytes.length; i += 128) {
        total += bytes[i];
        count++;
      }
      if (count > 0) {
        final avgLuma = total / count;
        _advisor.updateCameraMetrics(averageLuminance: avgLuma);
        _updateAdvisorAlert();
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final next = !_isTorchOn;
      await _cameraController!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() => _isTorchOn = next);
        _updateAdvisorAlert();
      }
    } catch (_) {}
  }

  Future<void> _loadExistingGraph() async {
    final existingNodes = await widget.repository.getNodes(widget.floor.id);
    final existingEdges = await widget.repository.getEdges(widget.floor.id);

    if (mounted) {
      setState(() {
        _nodes.addAll(existingNodes);
        _edges.addAll(existingEdges);
        if (_nodes.isNotEmpty) {
          _lastPlacedNode = _nodes.last;
          _odometryTracker.setLastPlacedNode(_lastPlacedNode);
        }
        _loading = false;
      });
    }
  }

  Future<void> _initAr() async {
    final granted = await ensureCameraPermission();
    if (!granted) return;

    try {
      final started = await ArBridge.instance.startMappingSession(widget.floor.id);
      if (mounted) {
        setState(() => _mappingSessionActive = started);
      }
    } catch (_) {}

    _arSubscription = ArBridge.instance.events.listen((event) {
      if (!mounted) return;
      if (event is PlaneDetectedEvent) {
        setState(() => _planeCount = event.planeCount);
      } else if (event is UserPoseEvent) {
        setState(() {
          _odometryTracker.updateUserPose(event.x, event.y, event.z);
          _updateAdvisorAlert();
        });
      } else if (event is TrackingStateChangedEvent) {
        setState(() {
          _advisor.setTrackingLost(event.state == TrackingState.lost);
          _updateAdvisorAlert();
        });
      }
    });
  }

  void _initSensors() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    // 1. Instant real-time Accelerometer step detection (Zero permissions, 50Hz immediate hardware stream)
    try {
      _accelSubscription = userAccelerometerEventStream().listen(
        _onUserAccelerometer,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}

    // 2. Hardware pedometer stream as complementary sensor
    _initPedometer();
  }

  void _onUserAccelerometer(UserAccelerometerEvent event) {
    if (!_isTrackingActive) return;
    // Magnitude of user linear acceleration (gravity isolated)
    final mag = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    final now = DateTime.now();
    if (mag >= _stepThreshold &&
        now.difference(_lastStepTime).inMilliseconds > _stepDebounceMs) {
      _lastStepTime = now;
      if (mounted) {
        setState(() {
          _odometryTracker.recordStep();
          _updateAdvisorAlert();
        });
      }
    }
  }

  void _toggleTracking() {
    setState(() {
      _isTrackingActive = !_isTrackingActive;
      if (_isTrackingActive) {
        _odometryTracker.startRecording();
      } else {
        _odometryTracker.pauseRecording();
      }
      _updateAdvisorAlert();
    });
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isTrackingActive
              ? '▶ AUTO-TRACKING ACTIVE: Footsteps tracked automatically!'
              : '⏸ TRACKING PAUSED: Walk tracking paused.',
        ),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _initPedometer() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final granted = await ensureActivityRecognitionPermission();
    if (!granted) return;

    try {
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _onStepCount(StepCount event) {
    if (!mounted) return;
    final current = event.steps;
    if (_lastCumulativeStepCount != null) {
      final delta = current - _lastCumulativeStepCount!;
      if (delta > 0 && delta < 50 && _isTrackingActive) {
        if (DateTime.now().difference(_lastStepTime).inMilliseconds > 600) {
          setState(() {
            for (int i = 0; i < delta; i++) {
              _odometryTracker.recordStep();
            }
            _updateAdvisorAlert();
          });
        }
      }
    }
    _lastCumulativeStepCount = current;
  }

  void _updateAdvisorAlert() {
    if (!mounted) return;
    final loopCandidate = _odometryTracker.checkLoopClosureCandidate(
      _nodes,
      thresholdMeters: 2.5,
      excludeNodeId: _lastPlacedNode?.id,
    );
    final loopDist = loopCandidate != null
        ? _odometryTracker.currentPosition.distanceTo(loopCandidate.position)
        : null;

    final alert = _advisor.evaluate(
      distanceFromLastNode: _odometryTracker.distanceFromLastNode,
      nodeCount: _nodes.length,
      loopCandidate: loopCandidate,
      loopCandidateDistance: loopDist,
    );

    if (alert?.message != _currentAlert?.message) {
      setState(() => _currentAlert = alert);
    }
  }

  void _handleAlertAction(AdvisorAlert alert) {
    if (alert.type == AlertType.lowLight) {
      _toggleTorch();
    } else if (alert.type == AlertType.loopClosureAvailable && alert.targetNode != null) {
      _closeCorridorLoop(alert.targetNode!);
    }
  }

  void _closeCorridorLoop(MapNode targetNode) {
    if (_lastPlacedNode == null || _lastPlacedNode!.id == targetNode.id) return;
    final dist = _lastPlacedNode!.position.distanceTo(targetNode.position);
    final edge = MapEdge(
      id: 'edge_${_lastPlacedNode!.id}_${targetNode.id}',
      fromNodeId: _lastPlacedNode!.id,
      toNodeId: targetNode.id,
      floorId: widget.floor.id,
      weight: double.parse(dist.toStringAsFixed(2)),
      type: EdgeType.walkable,
    );
    setState(() {
      _edges.add(edge);
      _currentAlert = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connected loop: "${_lastPlacedNode!.label}" ↔ "${targetNode.label}" (${dist.toStringAsFixed(1)}m)'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  void _turnLeft90() {
    setState(() {
      _orientationTracker.rotateHeading(-math.pi / 2);
      _odometryTracker.setHeading(_orientationTracker.headingRadians);
      _updateAdvisorAlert();
    });
  }

  void _turnRight90() {
    setState(() {
      _orientationTracker.rotateHeading(math.pi / 2);
      _odometryTracker.setHeading(_orientationTracker.headingRadians);
      _updateAdvisorAlert();
    });
  }

  void _turnAround180() {
    setState(() {
      _orientationTracker.rotateHeading(math.pi);
      _odometryTracker.setHeading(_orientationTracker.headingRadians);
      _updateAdvisorAlert();
    });
  }

  Future<void> _handleViewportTap(TapUpDetails details, BoxConstraints constraints) async {
    // 1. Check if user tapped directly on an existing 3D node
    final tappedNode = _lastPainter?.hitTestNode(
      details.localPosition,
      Size(constraints.maxWidth, constraints.maxHeight),
    );

    if (tappedNode != null) {
      if (_isLinkingMode) {
        _startManualLink(tappedNode);
      } else {
        setState(() => _selectedNode = tappedNode);
        _showNodeQuickActionSheet(tappedNode);
      }
      return;
    }

    if (_isLinkingMode) return;

    // 2. Tapped on floor plane: query real ARCore plane hit-test with odometry fallback
    final screenX = details.localPosition.dx / constraints.maxWidth;
    final screenY = details.localPosition.dy / constraints.maxHeight;
    if (screenY < 0.36) return;

    final depthFactor = ((0.85 - screenY) / 0.45).clamp(0.0, 1.0);
    final distanceMeters = double.parse((0.6 + depthFactor * 3.8).toStringAsFixed(1));

    setState(() {
      _targetDistanceAhead = distanceMeters;
      _selectedNode = null;
    });

    Position targetPos;
    final currentPos = _odometryTracker.currentPosition;
    final arHit = await ArBridge.instance.hitTest(
      screenX,
      screenY,
      currentX: currentPos.x,
      currentZ: currentPos.z,
    );

    if (arHit != null) {
      targetPos = Position(x: arHit.x, y: 0.0, z: arHit.z);
    } else {
      targetPos = _odometryTracker.calculateNodePosition(
        forwardOffsetMeters: distanceMeters,
      );
    }

    _showAddNodeDialog(targetPos);
  }

  void _showNodeQuickActionSheet(MapNode node) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final dist = _odometryTracker.currentPosition.distanceTo(node.position);
        final connectedEdges = _edges
            .where((e) => e.fromNodeId == node.id || e.toNodeId == node.id)
            .toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                    ),
                    child: const Icon(CupertinoIcons.placemark_fill,
                        color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${node.type.name.toUpperCase()} • ${dist.toStringAsFixed(1)}m away • ${connectedEdges.length} connections',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark_circle_fill,
                        color: Colors.white38),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(CupertinoIcons.link, size: 18),
                      label: const Text('Connect Path',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _isLinkingMode = true;
                          _linkSourceNode = node;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Selected "${node.label}". Now tap second node to link.')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFDC2626).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(CupertinoIcons.trash, size: 18),
                    label: const Text('Delete'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _deleteNode(node);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showAddNodeDialog(Position position) {
    NodeFormDialog.show(
      context: context,
      position: position,
      previousNodeLabel: _lastPlacedNode?.label,
      previousNodePosition: _lastPlacedNode?.position,
      initialDistance: _lastPlacedNode?.position.distanceTo(position),
      suggestedLabel: _nodes.isEmpty ? 'Entrance' : 'Room ${101 + _nodes.length}',
      initialType: _nodes.isEmpty ? NodeType.junction : NodeType.room,
      onConfirm: (label, type, confirmedPosition) {
        _confirmDropNode(label, type, confirmedPosition);
      },
    );
  }

  void _confirmDropNode(String label, NodeType type, Position position) {
    final newNodeId = 'node_${DateTime.now().millisecondsSinceEpoch}';
    final newNode = MapNode(
      id: newNodeId,
      floorId: widget.floor.id,
      type: type,
      label: label,
      position: position,
    );

    setState(() {
      _nodes.add(newNode);

      // Auto-Breadcrumb linking: automatically connect to previously placed node with true Euclidean distance
      if (_breadcrumbMode && _lastPlacedNode != null) {
        final distance = _lastPlacedNode!.position.distanceTo(position);
        final edge = MapEdge(
          id: 'edge_${_lastPlacedNode!.id}_${newNode.id}',
          fromNodeId: _lastPlacedNode!.id,
          toNodeId: newNode.id,
          floorId: widget.floor.id,
          weight: double.parse(distance.toStringAsFixed(2)),
          type: type == NodeType.stair
              ? EdgeType.stair
              : type == NodeType.elevator
                  ? EdgeType.elevator
                  : EdgeType.walkable,
        );
        _edges.add(edge);
      }

      _lastPlacedNode = newNode;
      _odometryTracker.setLastPlacedNode(newNode);
      _updateAdvisorAlert();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _breadcrumbMode && _nodes.length > 1
              ? 'Placed "$label" & auto-linked (${_edges.last.weight}m from "${_nodes[_nodes.length - 2].label}")'
              : 'Placed spatial node "$label"',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _undoLastNode() {
    if (_nodes.isEmpty) return;
    final removed = _nodes.removeLast();
    _edges.removeWhere((e) => e.fromNodeId == removed.id || e.toNodeId == removed.id);
    setState(() {
      _lastPlacedNode = _nodes.isNotEmpty ? _nodes.last : null;
      _odometryTracker.setLastPlacedNode(_lastPlacedNode);
      _updateAdvisorAlert();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${removed.label}"'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startManualLink(MapNode node) {
    if (_linkSourceNode == null) {
      setState(() {
        _linkSourceNode = node;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected "${node.label}". Now select destination node to link.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (_linkSourceNode!.id == node.id) {
      setState(() => _linkSourceNode = null);
    } else {
      final from = _linkSourceNode!;
      final to = node;
      final distance = from.position.distanceTo(to.position);

      final newEdge = MapEdge(
        id: 'edge_${from.id}_${to.id}',
        fromNodeId: from.id,
        toNodeId: to.id,
        floorId: widget.floor.id,
        weight: double.parse(distance.toStringAsFixed(2)),
        type: EdgeType.walkable,
      );

      setState(() {
        _edges.add(newEdge);
        _linkSourceNode = null;
        _isLinkingMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Linked "${from.label}" ↔ "${to.label}" (${distance.toStringAsFixed(2)}m)'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  void _deleteNode(MapNode node) {
    setState(() {
      _nodes.removeWhere((n) => n.id == node.id);
      _edges.removeWhere((e) => e.fromNodeId == node.id || e.toNodeId == node.id);
      if (_lastPlacedNode?.id == node.id) {
        _lastPlacedNode = _nodes.isNotEmpty ? _nodes.last : null;
        _odometryTracker.setLastPlacedNode(_lastPlacedNode);
      }
      _updateAdvisorAlert();
    });
  }

  Future<void> _saveAndExit() async {
    // 1. Pre-Save Graph Health Validation: check for isolated/orphaned nodes
    final isolated = _nodes.where((n) {
      return !_edges.any((e) => e.fromNodeId == n.id || e.toNodeId == n.id);
    }).toList();

    if (isolated.isNotEmpty && _nodes.length > 1) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Text('Graph Health Notice'),
            ],
          ),
          content: Text(
            '${isolated.length} node(s) (${isolated.map((n) => n.label).join(", ")}) have no connected walking paths. Users will not be able to navigate to them.\n\nSave anyway or keep editing to link them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep Editing'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF09090B)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _loading = true);

    // Save all nodes
    for (final node in _nodes) {
      await widget.repository.saveNode(node);
    }
    // Save all edges
    for (final edge in _edges) {
      await widget.repository.saveEdge(edge);
    }

    // Set origin anchor on floor if first node exists
    if (_nodes.isNotEmpty) {
      final updatedFloor = Floor(
        id: widget.floor.id,
        buildingId: widget.floor.buildingId,
        level: widget.floor.level,
        name: widget.floor.name,
        originAnchor: _nodes.first.position,
      );
      await widget.repository.saveFloor(updatedFloor);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${_nodes.length} nodes and ${_edges.length} edges successfully!'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  void _confirmClearFloorMap() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Floor Map?'),
        content: Text(
          'Are you sure you want to delete all ${_nodes.length} nodes and ${_edges.length} paths on this floor? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.repository.clearFloorMap(widget.floor.id);
              if (mounted) {
                setState(() {
                  _nodes.clear();
                  _edges.clear();
                  _lastPlacedNode = null;
                  _linkSourceNode = null;
                  _isLinkingMode = false;
                  _odometryTracker.reset();
                  _updateAdvisorAlert();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cleared all nodes and paths on this floor'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Clear Floor Map'),
          ),
        ],
      ),
    );
  }

  void _showInspector() {
    MappingInspectorSheet.show(
      context: context,
      nodes: _nodes,
      edges: _edges,
      linkSourceNode: _linkSourceNode,
      onStartLink: (node) {
        setState(() => _isLinkingMode = true);
        _startManualLink(node);
      },
      onDeleteNode: _deleteNode,
    );
  }

  IconData _alertIcon(AlertType type) {
    switch (type) {
      case AlertType.lowLight:
        return CupertinoIcons.lightbulb_fill;
      case AlertType.walkingTooFast:
        return CupertinoIcons.speedometer;
      case AlertType.badTilt:
        return CupertinoIcons.arrow_down_right_arrow_up_left;
      case AlertType.featurelessSurface:
        return CupertinoIcons.eye_slash_fill;
      case AlertType.tooCloseToNode:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case AlertType.loopClosureAvailable:
        return CupertinoIcons.link;
      case AlertType.trackingLost:
        return CupertinoIcons.exclamationmark_octagon_fill;
      case AlertType.readyToMap:
        return CupertinoIcons.checkmark_seal_fill;
    }
  }

  Color _alertBackgroundColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.danger:
        return const Color(0xFFDC2626).withValues(alpha: 0.95);
      case AlertSeverity.warning:
        return const Color(0xFFD97706).withValues(alpha: 0.95);
      case AlertSeverity.success:
        return const Color(0xFF059669).withValues(alpha: 0.95);
      case AlertSeverity.info:
        return const Color(0xFF1E293B).withValues(alpha: 0.95);
    }
  }

  Color _alertBorderColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.danger:
        return const Color(0xFFEF4444);
      case AlertSeverity.warning:
        return const Color(0xFFFBBF24);
      case AlertSeverity.success:
        return const Color(0xFF34D399);
      case AlertSeverity.info:
        return const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin AR Mapping',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              '${widget.building.name} • ${widget.floor.name}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'View Placed Nodes',
            icon: Badge(
              backgroundColor: const Color(0xFF09090B),
              label: Text('${_nodes.length}'),
              child: const Icon(CupertinoIcons.list_bullet_indent, size: 22),
            ),
            onPressed: _showInspector,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF09090B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _nodes.isEmpty ? null : _saveAndExit,
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 20),
            tooltip: 'Floor options',
            onSelected: (value) {
              if (value == 'clear') {
                _confirmClearFloorMap();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                enabled: _nodes.isNotEmpty || _edges.isNotEmpty,
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.trash, size: 18, color: Color(0xFFDC2626)),
                    SizedBox(width: 10),
                    Text('Clear Floor Map', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // 1. AR Live Camera Viewfinder & Hit-Test Surface
                    Positioned.fill(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_cameraInitialized && _cameraController != null)
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize?.height ?? constraints.maxWidth,
                                height: _cameraController!.value.previewSize?.width ?? constraints.maxHeight,
                                child: CameraPreview(_cameraController!),
                              ),
                            )
                          else if (Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST'))
                            const NativeArSceneView()
                          else
                            Container(color: const Color(0xFF09090B)),

                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) => _handleViewportTap(details, constraints),
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _orientationTracker.rotateHeading(details.primaryDelta! * 0.006);
                                _odometryTracker.setHeading(_orientationTracker.headingRadians);
                                _updateAdvisorAlert();
                              });
                            },
                            child: AnimatedBuilder(
                              animation: _pulseAnimationController,
                              builder: (context, _) {
                                final painter = ArMappingPerspectivePainter(
                                  nodes: _nodes,
                                  edges: _edges,
                                  selectedNode: _selectedNode,
                                  linkSourceNode: _linkSourceNode,
                                  currentUserPosition: _odometryTracker.currentPosition,
                                  headingRadians: _orientationTracker.headingRadians,
                                  pitchRadians: _orientationTracker.pitchRadians,
                                  rollRadians: _orientationTracker.rollRadians,
                                  breadcrumbs: _odometryTracker.breadcrumbTrail,
                                  targetFloorPosition: _targetFloorPosition,
                                  targetDistanceAhead: _targetDistanceAhead,
                                  isReticleVisible: !_isLinkingMode,
                                  animationProgress: _pulseAnimationController.value,
                                );
                                _lastPainter = painter;

                                return CustomPaint(
                                  painter: painter,
                                  child: const SizedBox.expand(),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 2. Top Status HUD: Tracking, Distance Walked, Auto-Link
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _toggleTracking,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isTrackingActive ? const Color(0xFF10B981) : Colors.amberAccent,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isTrackingActive ? const Color(0xFF10B981) : Colors.amberAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _nodes.isEmpty
                                        ? (_mappingSessionActive ? 'AR Ready' : 'Initializing AR...')
                                        : (_isTrackingActive
                                            ? '● LIVE: ${_odometryTracker.distanceFromLastNode.toStringAsFixed(1)}m'
                                            : '⏸ PAUSED: ${_odometryTracker.distanceFromLastNode.toStringAsFixed(1)}m'),
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    _isTrackingActive ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                    size: 11,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Breadcrumb mode toggle
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'Auto-Link',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(width: 6),
                                Transform.scale(
                                  scale: 0.75,
                                  child: Switch(
                                    value: _breadcrumbMode,
                                    onChanged: (val) {
                                      setState(() => _breadcrumbMode = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 3. Environmental & Tracking Quality Advisory Banner
                    if (_currentAlert != null)
                      Positioned(
                        top: 68,
                        left: 16,
                        right: _nodes.isNotEmpty ? 144 : 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _alertBackgroundColor(_currentAlert!.severity),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _alertBorderColor(_currentAlert!.severity), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _alertIcon(_currentAlert!.type),
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _currentAlert!.message,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (_currentAlert!.actionLabel != null) ...[
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                                    foregroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _handleAlertAction(_currentAlert!),
                                  child: Text(
                                    _currentAlert!.actionLabel!,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    // 4. Linking Mode Banner
                    if (_isLinkingMode)
                      Positioned(
                        top: _currentAlert != null ? 120 : 68,
                        left: 16,
                        right: _nodes.isNotEmpty ? 144 : 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF09090B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.link, color: Colors.white, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _linkSourceNode == null
                                      ? 'Select first node to connect'
                                      : 'Selected "${_linkSourceNode!.label}". Select second node.',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isLinkingMode = false;
                                    _linkSourceNode = null;
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 5. Corner Mini-Map Radar (Floating Top-Right)
                    if (_nodes.isNotEmpty)
                      Positioned(
                        top: 72,
                        right: 16,
                        child: MappingMiniMap(
                          nodes: _nodes,
                          edges: _edges,
                          currentUserPosition: _odometryTracker.currentPosition,
                          headingRadians: _orientationTracker.headingRadians,
                          selectedNode: _selectedNode,
                          breadcrumbs: _odometryTracker.breadcrumbTrail,
                        ),
                      ),

                    // 6. Quick Turn Controls (Corridor Angle Stepper)
                    Positioned(
                      top: _nodes.isNotEmpty ? 204 : 72,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: _calibrateForward,
                              borderRadius: BorderRadius.circular(8),
                              child: Tooltip(
                                message: 'Tap to align forward',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_orientationTracker.headingDegrees.round()}°',
                                    style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              tooltip: 'Turn Left 90°',
                              icon: const Icon(CupertinoIcons.arrow_turn_up_left, color: Colors.white, size: 18),
                              onPressed: _turnLeft90,
                            ),
                            const SizedBox(height: 2),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              tooltip: 'Turn Right 90°',
                              icon: const Icon(CupertinoIcons.arrow_turn_up_right, color: Colors.white, size: 18),
                              onPressed: _turnRight90,
                            ),
                            const SizedBox(height: 2),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              tooltip: 'Turn Around 180°',
                              icon: const Icon(CupertinoIcons.arrow_2_circlepath, color: Colors.white70, size: 16),
                              onPressed: _turnAround180,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 7. Dual Placement & Reticle Distance Bar (Above Walk Track Button)
                    Positioned(
                      bottom: 154,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090D16).withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Distance preset chips
                            Row(
                              children: [
                                const Icon(CupertinoIcons.scope, size: 14, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 6),
                                const Text(
                                  'Target:',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [1.0, 1.8, 2.5, 3.5].map((dist) {
                                        final isCurrent = (_targetDistanceAhead - dist).abs() < 0.2;
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () {
                                              setState(() => _targetDistanceAhead = dist);
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isCurrent ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isCurrent ? const Color(0xFF38BDF8) : Colors.white12,
                                                ),
                                              ),
                                              child: Text(
                                                '${dist.toStringAsFixed(1)}m',
                                                style: TextStyle(
                                                  color: isCurrent ? Colors.black : Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Dual Drop Buttons
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(CupertinoIcons.plus_circle_fill, size: 16),
                                    label: Text(
                                      'Drop at Target (${_targetDistanceAhead.toStringAsFixed(1)}m)',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onPressed: () => _showAddNodeDialog(_targetFloorPosition),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(CupertinoIcons.location_fill, size: 16),
                                    label: const Text(
                                      'Drop at Feet',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onPressed: () => _showAddNodeDialog(_odometryTracker.currentPosition),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 8. Bottom Floating Action Toolbar
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: MappingControlsBar(
                        nodeCount: _nodes.length,
                        isLinkingMode: _isLinkingMode,
                        distanceFromLastNode: _nodes.isNotEmpty ? _odometryTracker.distanceFromLastNode : null,
                        isTorchOn: _isTorchOn,
                        onToggleTorch: _toggleTorch,
                        onUndo: _undoLastNode,
                        onAddNode: () {
                          _showAddNodeDialog(_targetFloorPosition);
                        },
                        onToggleLinkingMode: () {
                          setState(() => _isLinkingMode = !_isLinkingMode);
                          _showInspector();
                        },
                        onOpenInspector: _showInspector,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
