import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/map_repository.dart';
import '../logic/bezier_smoother.dart';
import '../logic/pathfinder.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';
import '../native/ar_bridge.dart';
import '../native/camera_permission.dart';

/// AR Indoor Navigation Screen with real-time SceneView / ARCore feed,
/// quadratic Bezier path smoothing, dynamic turn-by-turn guidance HUD,
/// wall/obstacle depth occlusion awareness, and responsive 3D/2D directional turn arrows.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.repository,
    required this.floor,
    required this.destination,
  });

  final MapRepository repository;
  final Floor floor;
  final MapNode destination;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin {
  List<MapNode> _allNodes = [];
  List<MapEdge> _allEdges = [];
  List<MapNode> _path = [];
  List<SmoothedPathPoint> _smoothedPoints = [];
  List<TurnInstruction> _turnInstructions = [];
  int _currentInstructionIndex = 0;

  bool _loading = true;
  bool _arSessionActive = false;
  bool _show2dFloorMap = false;
  TrackingState _trackingState = TrackingState.normal;
  String? _obstacleWarning;
  StreamSubscription<ArEvent>? _arSubscription;

  CameraController? _cameraController;
  bool _cameraInitialized = false;

  late final AnimationController _arrowAnimationController;

  Vector3? _userPosition;
  Timer? _simulationTimer;
  bool _isSimulatingWalk = false;

  @override
  void initState() {
    super.initState();
    _arrowAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _arrowAnimationController.repeat();
    }
    _load();
    _subscribeToArEvents();
    _initCamera();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _arrowAnimationController.dispose();
    _arSubscription?.cancel();
    _cameraController?.dispose();
    ArBridge.instance.clearPath().catchError((Object _) {});
    ArBridge.instance.stopArSession().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
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
      }
    } catch (_) {}
  }

  void _subscribeToArEvents() {
    _arSubscription = ArBridge.instance.events.listen((event) {
      if (!mounted) return;
      if (event is TrackingStateChangedEvent) {
        setState(() => _trackingState = event.state);
      } else if (event is UserPoseEvent) {
        _onUserPoseUpdated(event.x, event.y, event.z);
      } else if (event is ApproachingNodeEvent) {
        _advanceToNode(event.nodeId);
      } else if (event is ObstacleDetectedEvent) {
        setState(() {
          _obstacleWarning = '${event.description} (${event.distance.toStringAsFixed(1)}m)';
        });
      }
    });
  }

  void _onUserPoseUpdated(double x, double y, double z) {
    if (_isSimulatingWalk) return;
    _updateUserPosition(Vector3(x, y, z));
  }

  void _updateUserPosition(Vector3 newPos) {
    setState(() {
      _userPosition = newPos;

      // Auto-advance turn instruction when user approaches within 1.8m of upcoming waypoint
      if (_currentInstruction != null && _currentInstructionIndex < _turnInstructions.length - 1) {
        final target = _currentInstruction!.position;
        final dx = target.x - newPos.x;
        final dz = target.z - newPos.z;
        final dist = math.sqrt(dx * dx + dz * dz);
        if (dist < 1.8) {
          _currentInstructionIndex++;
        }
      }
    });
  }

  void _toggleWalkSimulation() {
    if (_isSimulatingWalk) {
      _simulationTimer?.cancel();
      setState(() => _isSimulatingWalk = false);
    } else {
      if (_smoothedPoints.isEmpty) return;
      setState(() => _isSimulatingWalk = true);

      int currentPointIdx = 0;
      if (_userPosition != null) {
        double minD = double.infinity;
        for (int i = 0; i < _smoothedPoints.length; i++) {
          final p = _smoothedPoints[i].position;
          final d = (p.x - _userPosition!.x) * (p.x - _userPosition!.x) +
              (p.z - _userPosition!.z) * (p.z - _userPosition!.z);
          if (d < minD) {
            minD = d;
            currentPointIdx = i;
          }
        }
      }

      _simulationTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (currentPointIdx < _smoothedPoints.length - 1) {
          currentPointIdx++;
          final pt = _smoothedPoints[currentPointIdx].position;
          _updateUserPosition(pt);
        } else {
          timer.cancel();
          setState(() => _isSimulatingWalk = false);
        }
      });
    }
  }

  void _advanceToNode(String nodeId) {
    if (_turnInstructions.isEmpty) return;
    for (int i = _currentInstructionIndex; i < _turnInstructions.length; i++) {
      if (_turnInstructions[i].nodeLabel.toLowerCase() == nodeId.toLowerCase()) {
        setState(() => _currentInstructionIndex = i);
        break;
      }
    }
  }

  Future<void> _load() async {
    final nodes = await widget.repository.getNodes(widget.floor.id);
    final edges = await widget.repository.getEdges(widget.floor.id);

    // Resolve start node dynamically: look for Entrance, otherwise pick first non-destination node
    final startNode = nodes.firstWhere(
      (n) => n.id == 'entrance' || n.label.toLowerCase().contains('entrance'),
      orElse: () => nodes.firstWhere(
        (n) => n.id != widget.destination.id,
        orElse: () => widget.destination,
      ),
    );

    final path = findPath(
      nodes: nodes,
      edges: edges,
      startNodeId: startNode.id,
      endNodeId: widget.destination.id,
    );

    final smoothed = BezierSmoother.smoothPath(path);
    final instructions = BezierSmoother.extractTurnInstructions(path);

    setState(() {
      _allNodes = nodes;
      _allEdges = edges;
      _path = path;
      _smoothedPoints = smoothed;
      _turnInstructions = instructions;
      _currentInstructionIndex = 0;
      _loading = false;
    });

    // Request camera permission for native AR session
    final granted = await ensureCameraPermission();
    if (!granted) return;

    try {
      final started = await ArBridge.instance.startArSession(widget.floor.id);
      if (mounted) setState(() => _arSessionActive = started);

      // Render 3D Bezier smoothed arrows in AR SceneView
      if (smoothed.isNotEmpty) {
        await ArBridge.instance.renderSmoothedPath(
          smoothed.map((p) => p.toMap()).toList(),
        );
      }
    } catch (_) {}
  }

  double get _currentStepRemainingDistance {
    if (_turnInstructions.isEmpty) return 0.0;
    final currentInst = _currentInstruction!;
    if (_userPosition != null) {
      final dx = currentInst.position.x - _userPosition!.x;
      final dz = currentInst.position.z - _userPosition!.z;
      return math.sqrt(dx * dx + dz * dz);
    }
    return currentInst.distanceToTurn;
  }

  double get _totalDistance {
    if (_turnInstructions.isEmpty) {
      return _smoothedPoints.isEmpty ? 0.0 : _smoothedPoints.last.distanceAlongPath;
    }
    double dist = _currentStepRemainingDistance;
    for (int i = _currentInstructionIndex; i < _turnInstructions.length - 1; i++) {
      final p1 = _turnInstructions[i].position;
      final p2 = _turnInstructions[i + 1].position;
      final dx = p2.x - p1.x;
      final dz = p2.z - p1.z;
      dist += math.sqrt(dx * dx + dz * dz);
    }
    return dist;
  }

  TurnInstruction? get _currentInstruction {
    if (_turnInstructions.isEmpty) return null;
    final idx = _currentInstructionIndex.clamp(0, _turnInstructions.length - 1);
    return _turnInstructions[idx];
  }

  IconData _getTurnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) return CupertinoIcons.arrow_turn_up_left;
    if (lower.contains('right')) return CupertinoIcons.arrow_turn_up_right;
    if (lower.contains('arrive')) return CupertinoIcons.placemark_fill;
    return CupertinoIcons.arrow_up;
  }

  Widget _buildArViewport() {
    return AnimatedBuilder(
      animation: _arrowAnimationController,
      builder: (context, _) {
        if (_cameraInitialized && _cameraController != null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? MediaQuery.of(context).size.width,
                  height: _cameraController!.value.previewSize?.width ?? MediaQuery.of(context).size.height,
                  child: CameraPreview(_cameraController!),
                ),
              ),
              _ArPerspectiveSimulationView(
                smoothedPoints: _smoothedPoints,
                turnInstructions: _turnInstructions,
                currentInstructionIndex: _currentInstructionIndex,
                destinationLabel: widget.destination.label,
                animationProgress: _arrowAnimationController.value,
                userPosition: _userPosition,
                isOverlay: true,
              ),
            ],
          );
        }

        // High-fidelity AR Simulation View for desktop/test/preview
        return _ArPerspectiveSimulationView(
          smoothedPoints: _smoothedPoints,
          turnInstructions: _turnInstructions,
          currentInstructionIndex: _currentInstructionIndex,
          destinationLabel: widget.destination.label,
          animationProgress: _arrowAnimationController.value,
          userPosition: _userPosition,
          isOverlay: false,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentInst = _currentInstruction;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 1. Live AR Viewport or Full 2D Floor Map
                Positioned.fill(
                  child: _show2dFloorMap
                      ? _FloorMapView(
                          nodes: _allNodes,
                          edges: _allEdges,
                          path: _path,
                          turnInstructions: _turnInstructions,
                          currentInstructionIndex: _currentInstructionIndex,
                          destination: widget.destination,
                          userPosition: _userPosition,
                        )
                      : _buildArViewport(),
                ),

                // 2. Top App Bar & Tracking Status Bar
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.65),
                        child: IconButton(
                          icon: const Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (_arSessionActive && _trackingState == TrackingState.normal)
                                    ? Colors.white
                                    : Colors.white60,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              !_arSessionActive
                                  ? 'AR Initializing...'
                                  : (_trackingState == TrackingState.normal
                                      ? 'AR Active • Depth Occlusion ON'
                                      : 'Tracking Limited'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Walk Simulation Toggle Button
                      Container(
                        decoration: BoxDecoration(
                          color: _isSimulatingWalk
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isSimulatingWalk ? Colors.white : Colors.white12,
                          ),
                        ),
                        child: IconButton(
                          tooltip: _isSimulatingWalk ? 'Pause Walk' : 'Simulate Walk',
                          icon: Icon(
                            _isSimulatingWalk ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _toggleWalkSimulation,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 2D Map / AR 3D View Toggle Button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: IconButton(
                          tooltip: _show2dFloorMap ? 'Switch to AR View' : 'Switch to 2D Floor Map',
                          icon: Icon(
                            _show2dFloorMap ? CupertinoIcons.cube_box : CupertinoIcons.map,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() => _show2dFloorMap = !_show2dFloorMap);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Floating Turn-by-Turn Guidance HUD
                if (currentInst != null)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 60,
                    left: 16,
                    right: 16,
                    child: Card(
                      color: const Color(0xFF09090B).withValues(alpha: 0.92),
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Colors.white12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getTurnIcon(currentInst.instruction),
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currentInst.instruction,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_currentStepRemainingDistance.toStringAsFixed(1)}m • Total: ${_totalDistance.toStringAsFixed(1)}m to ${widget.destination.label}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_turnInstructions.length > 1)
                              IconButton(
                                tooltip: 'Next Step',
                                icon: const Icon(CupertinoIcons.forward_end_fill, color: Colors.white70, size: 18),
                                onPressed: _currentInstructionIndex < _turnInstructions.length - 1
                                    ? () => setState(() => _currentInstructionIndex++)
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 4. Dynamic Obstacle Warning Banner
                if (_obstacleWarning != null)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 160,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.white, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _obstacleWarning!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 5. Mini-Map Radar (Floating in bottom-right corner when in AR mode)
                if (!_show2dFloorMap && _allNodes.isNotEmpty)
                  Positioned(
                    bottom: 96,
                    right: 16,
                    child: _MiniMapRadar(
                      nodes: _allNodes,
                      edges: _allEdges,
                      path: _path,
                      turnInstructions: _turnInstructions,
                      currentInstructionIndex: _currentInstructionIndex,
                      userPosition: _userPosition,
                      onTap: () => setState(() => _show2dFloorMap = true),
                    ),
                  ),

                // 6. Bottom Route Drawer / Step-by-Step Milestones
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF09090B).withValues(alpha: 0.96),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: const Border(top: BorderSide(color: Colors.white12)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Route to ${widget.destination.label}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_path.length} waypoints • ${_smoothedPoints.length} AR arrows placed',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('End Route', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// AR Perspective Simulation View:
/// Renders a dynamic 3D-perspective view with animated floating
/// directional chevrons and floor turn indicators following the Bezier curve.
class _ArPerspectiveSimulationView extends StatelessWidget {
  final List<SmoothedPathPoint> smoothedPoints;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final String destinationLabel;
  final double animationProgress;
  final Vector3? userPosition;
  final bool isOverlay;

  const _ArPerspectiveSimulationView({
    required this.smoothedPoints,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    required this.destinationLabel,
    required this.animationProgress,
    this.userPosition,
    this.isOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isOverlay ? Colors.transparent : const Color(0xFF070B14),
      child: CustomPaint(
        painter: _ArPerspectivePainter(
          points: smoothedPoints,
          turnInstructions: turnInstructions,
          activeStep: currentInstructionIndex,
          animationProgress: animationProgress,
          destinationLabel: destinationLabel,
          userPosition: userPosition,
          isOverlay: isOverlay,
        ),
        child: isOverlay
            ? const SizedBox.expand()
            : Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.cube_box,
                      color: Colors.white12,
                      size: 64,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AR Guidance View Active',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Directional arrows aligned with corridor trajectory',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Custom painter simulating perspective AR guidance arrows on the floor.
/// Computes accurate 3D corridor perspective projection from camera anchor,
/// rendering directional flowing chevrons, 3D floor curved turn arrows, and floating badges.
class _ArPerspectivePainter extends CustomPainter {
  final List<SmoothedPathPoint> points;
  final List<TurnInstruction> turnInstructions;
  final int activeStep;
  final double animationProgress;
  final String destinationLabel;
  final Vector3? userPosition;
  final bool isOverlay;

  _ArPerspectivePainter({
    required this.points,
    required this.turnInstructions,
    required this.activeStep,
    required this.animationProgress,
    required this.destinationLabel,
    this.userPosition,
    this.isOverlay = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // Horizon line for 3D corridor perspective
    final horizonY = height * 0.35;
    final originX = width * 0.5;
    final originY = height * 0.82;

    // 1. Draw floor grid when in standalone simulation mode
    if (!isOverlay) {
      final floorGradient = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B14), Color(0xFF0F172A)],
        ).createShader(Rect.fromLTWH(0, horizonY, width, height - horizonY));
      canvas.drawRect(Rect.fromLTWH(0, horizonY, width, height - horizonY), floorGradient);

      final horizonPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.25)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, horizonY), Offset(width, horizonY), horizonPaint);

      final gridPaint = Paint()
        ..color = Colors.cyan.withValues(alpha: 0.08)
        ..strokeWidth = 1.0;

      for (double x = 0; x <= width; x += width / 8) {
        canvas.drawLine(Offset(originX, horizonY), Offset(x, height), gridPaint);
      }
      for (double y = horizonY; y <= height; y += (height - horizonY) / 6) {
        canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
      }
    }

    // 2. Camera anchor position and forward direction
    final Vector3 anchorPos = userPosition ??
        (activeStep < turnInstructions.length
            ? turnInstructions[activeStep].position
            : points.first.position);

    // Find closest smoothed point to current anchor
    int startIdx = 0;
    double minD = double.infinity;
    for (int i = 0; i < points.length; i++) {
      final p = points[i].position;
      final d = (p.x - anchorPos.x) * (p.x - anchorPos.x) + (p.z - anchorPos.z) * (p.z - anchorPos.z);
      if (d < minD) {
        minD = d;
        startIdx = i;
      }
    }

    // Determine forward heading vector F
    double fx = 0.0;
    double fz = 1.0;
    if (startIdx < points.length - 1) {
      final lookAhead = math.min(startIdx + 4, points.length - 1);
      final pNext = points[lookAhead].position;
      final dx = pNext.x - points[startIdx].position.x;
      final dz = pNext.z - points[startIdx].position.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len > 0.001) {
        fx = dx / len;
        fz = dz / len;
      }
    }
    // Right vector R (perpendicular to F, pointing right)
    final rx = fz;
    final rz = -fx;

    // Perspective projection function from 3D world meters into 2D screen coordinates
    Offset project(Vector3 pos) {
      final dx = pos.x - anchorPos.x;
      final dz = pos.z - anchorPos.z;

      final zCam = dx * fx + dz * fz;
      final xCam = dx * rx + dz * rz;

      final s = 4.5 / (4.5 + math.max(0.0, zCam));
      final sy = horizonY + (originY - horizonY) * s;
      final lateralScale = width * 0.22;
      final sx = originX + (xCam * lateralScale) * s;

      return Offset(sx.clamp(-80.0, width + 80.0), sy);
    }

    final visiblePoints = points.sublist(startIdx);
    if (visiblePoints.isEmpty) return;

    final screenOffsets = <Offset>[];
    for (final pt in visiblePoints) {
      screenOffsets.add(project(pt.position));
    }

    // 3. Draw smoothed path glow line
    if (screenOffsets.length >= 2) {
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.28)
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final linePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(screenOffsets.first.dx, screenOffsets.first.dy);
      for (int i = 1; i < screenOffsets.length; i++) {
        path.lineTo(screenOffsets[i].dx, screenOffsets[i].dy);
      }

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, linePaint);

      // Draw subtle AR feature/tracking sparkle points like in real ARCore
      _drawTrackingFeatureDots(canvas, screenOffsets, horizonY, originY);
    }

    // 4. Draw large corridor-spanning directional chevrons matching real AR navigation
    if (screenOffsets.length >= 2) {
      final numChevrons = math.min(7, math.max(4, (screenOffsets.length / 3).round()));
      for (int c = 0; c < numChevrons; c++) {
        // Place chevrons starting right in the immediate foreground through to the mid-distance
        final ratio = ((c + 0.15) / numChevrons).clamp(0.0, 0.95);
        final idx = (ratio * (screenOffsets.length - 1)).round().clamp(0, screenOffsets.length - 2);

        final current = screenOffsets[idx];
        final next = screenOffsets[idx + 1];

        final dx = next.dx - current.dx;
        final dy = next.dy - current.dy;
        final angle = math.atan2(dy, dx);

        final depthRatio = ((current.dy - horizonY) / (originY - horizonY)).clamp(0.18, 1.0);
        final scale = 0.38 + 0.62 * depthRatio;

        final pulsePhase = (ratio - animationProgress) % 1.0;
        final brightness = (0.75 + 0.25 * math.sin((pulsePhase + 1.0) % 1.0 * math.pi)).clamp(0.55, 1.0);

        _drawChevron(canvas, current, angle, scale, brightness, width);
      }

      // Draw AR floor plane tracking ring in the foreground matching real ARCore tracking
      final fgPos = screenOffsets.first;
      final reticlePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final reticleGlow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      final reticleCenter = Offset(fgPos.dx - 85.0, math.min(height - 45.0, fgPos.dy + 35.0));
      canvas.drawCircle(reticleCenter, 22.0, reticleGlow);
      canvas.drawCircle(reticleCenter, 22.0, reticlePaint);
    }

    // 5. Draw turn indicator arrows at each upcoming turn (Left, Right, Arrive)
    for (int i = activeStep; i < turnInstructions.length; i++) {
      final inst = turnInstructions[i];
      final pos = project(inst.position);

      if (pos.dy < horizonY - 30 || pos.dy > height + 40) continue;

      final depthRatio = ((pos.dy - horizonY) / (originY - horizonY)).clamp(0.3, 1.0);
      final isCurrent = i == activeStep;
      final lower = inst.instruction.toLowerCase();

      if (lower.contains('left')) {
        _drawTurnMarker(
          canvas: canvas,
          pos: pos,
          isLeft: true,
          label: 'TURN LEFT',
          distance: inst.distanceToTurn,
          scale: depthRatio,
          isCurrent: isCurrent,
        );
      } else if (lower.contains('right')) {
        _drawTurnMarker(
          canvas: canvas,
          pos: pos,
          isLeft: false,
          label: 'TURN RIGHT',
          distance: inst.distanceToTurn,
          scale: depthRatio,
          isCurrent: isCurrent,
        );
      } else if (lower.contains('arrive')) {
        _drawArrivalMarker(
          canvas: canvas,
          pos: pos,
          label: destinationLabel,
          scale: depthRatio,
        );
      }
    }
  }

  void _drawChevron(
    Canvas canvas,
    Offset pos,
    double angle,
    double scale,
    double brightness,
    double screenWidth,
  ) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    // Big corridor-width chevron ribbon (matching real AR navigation image)
    // Spans 70-80% of corridor width in foreground, scaling with floor depth
    final w = math.min(screenWidth * 0.78, 290.0) * scale;     // Wide lateral span across hallway floor
    final lTip = 68.0 * scale;                                 // Forward tip reach
    final lBand = 48.0 * scale;                                // Chevron ribbon band thickness

    final path = Path();
    path.moveTo(lTip, 0);                    // Front tip
    path.lineTo(0, -w * 0.5);                // Front left wing
    path.lineTo(-lBand, -w * 0.5);           // Back left wing
    path.lineTo(lTip - lBand, 0);            // Back inner notch
    path.lineTo(-lBand, w * 0.5);            // Back right wing
    path.lineTo(0, w * 0.5);                 // Front right wing
    path.close();

    // 1. Soft glowing outer haze bloom
    final outerHaze = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.40 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0 * scale
      ..strokeJoin = StrokeJoin.round;

    // 2. Translucent luminous cyan body fill (shows floor through slightly)
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF00F5FF).withValues(alpha: 0.78 * brightness),
          const Color(0xFF38BDF8).withValues(alpha: 0.88 * brightness),
          const Color(0xFF00F5FF).withValues(alpha: 0.78 * brightness),
        ],
      ).createShader(Rect.fromLTWH(-lBand, -w * 0.5, lTip + lBand, w))
      ..style = PaintingStyle.fill;

    // 3. Crisp luminous cyan-white perimeter border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeJoin = StrokeJoin.round;

    // 4. Highlight on front V-arrowhead (crisp white leading edge)
    final leadingV = Path();
    leadingV.moveTo(0, -w * 0.5);
    leadingV.lineTo(lTip, 0);
    leadingV.lineTo(0, w * 0.5);

    final leadingVPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, outerHaze);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
    canvas.drawPath(leadingV, leadingVPaint);

    canvas.restore();
  }

  void _drawTrackingFeatureDots(
    Canvas canvas,
    List<Offset> offsets,
    double horizonY,
    double originY,
  ) {
    final rand = math.Random(101);
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < offsets.length; i += 2) {
      final pt = offsets[i];
      final depth = ((pt.dy - horizonY) / (originY - horizonY)).clamp(0.2, 1.0);

      for (int j = 0; j < 3; j++) {
        final offsetX = (rand.nextDouble() - 0.5) * 160.0 * depth;
        final offsetY = (rand.nextDouble() - 0.5) * 45.0 * depth;
        final isGold = rand.nextBool();

        dotPaint.color = (isGold ? const Color(0xFFFDE047) : Colors.white)
            .withValues(alpha: (0.35 + rand.nextDouble() * 0.45) * depth);

        final dotRadius = (1.5 + rand.nextDouble() * 2.0) * depth;
        canvas.drawCircle(Offset(pt.dx + offsetX, pt.dy + offsetY), dotRadius, dotPaint);
      }
    }
  }

  void _drawTurnMarker({
    required Canvas canvas,
    required Offset pos,
    required bool isLeft,
    required String label,
    required double distance,
    required double scale,
    required bool isCurrent,
  }) {
    final turnColor = isCurrent ? const Color(0xFFF59E0B) : const Color(0xFF00E5FF);

    // 1. Draw 3D curved turn arrow on the floor surface
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    if (!isLeft) {
      canvas.scale(-1, 1); // Mirror across Y for right turn
    }

    final arrowScale = scale * 1.2;
    final stem = Path();
    stem.moveTo(0, 14 * arrowScale);
    stem.quadraticBezierTo(0, -6 * arrowScale, -20 * arrowScale, -8 * arrowScale);

    final stemGlow = Paint()
      ..color = turnColor.withValues(alpha: 0.4)
      ..strokeWidth = 8.0 * arrowScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final stemPaint = Paint()
      ..color = turnColor
      ..strokeWidth = 4.5 * arrowScale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(stem, stemGlow);
    canvas.drawPath(stem, stemPaint);

    // Arrowhead pointing left
    final head = Path();
    head.moveTo(-30 * arrowScale, -8 * arrowScale); // Tip
    head.lineTo(-18 * arrowScale, -18 * arrowScale);
    head.lineTo(-18 * arrowScale, 2 * arrowScale);
    head.close();

    final headGlow = Paint()
      ..color = turnColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * arrowScale;

    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(head, headGlow);
    canvas.drawPath(head, headPaint);
    canvas.restore();

    // 2. Vertical laser guideline from floor up to floating badge
    final badgeY = pos.dy - (44.0 * scale);
    final guidePaint = Paint()
      ..color = turnColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 12), guidePaint);

    // 3. Floating 3D AR Turn Badge
    final badgeWidth = 115.0 * scale;
    final badgeHeight = 28.0 * scale;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(pos.dx, badgeY),
        width: badgeWidth,
        height: badgeHeight,
      ),
      Radius.circular(14.0 * scale),
    );

    final badgeBg = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;

    final badgeBorder = Paint()
      ..color = turnColor
      ..strokeWidth = 1.5 * scale
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(badgeRect, badgeBg);
    canvas.drawRRect(badgeRect, badgeBorder);

    // Draw text inside badge
    final textSpan = TextSpan(
      text: '$label  ${isLeft ? '←' : '→'}',
      style: TextStyle(
        color: Colors.white,
        fontSize: (11.0 * scale).clamp(9.0, 14.0),
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, badgeY - textPainter.height / 2),
    );
  }

  void _drawArrivalMarker({
    required Canvas canvas,
    required Offset pos,
    required String label,
    required double scale,
  }) {
    // 1. Concentric ripple rings on the floor
    final ringPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.35)
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;

    final innerFill = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;

    final pulseRadius = (16.0 + 8.0 * (1.0 - animationProgress)) * scale;
    canvas.drawCircle(pos, pulseRadius, ringPaint);
    canvas.drawCircle(pos, 10.0 * scale, innerFill);

    // 2. Guideline to floating destination beacon
    final badgeY = pos.dy - (48.0 * scale);
    final guidePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(pos.dx, pos.dy), Offset(pos.dx, badgeY + 12), guidePaint);

    // 3. Floating Destination Pin Badge
    final badgeWidth = 120.0 * scale;
    final badgeHeight = 28.0 * scale;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(pos.dx, badgeY),
        width: badgeWidth,
        height: badgeHeight,
      ),
      Radius.circular(14.0 * scale),
    );

    final badgeBg = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;

    final badgeBorder = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 1.5 * scale
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(badgeRect, badgeBg);
    canvas.drawRRect(badgeRect, badgeBorder);

    final textSpan = TextSpan(
      text: '★ $label',
      style: TextStyle(
        color: Colors.white,
        fontSize: (11.0 * scale).clamp(9.0, 13.0),
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, badgeY - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ArPerspectivePainter oldDelegate) => true;
}

/// Floating mini-map radar widget showing top-down floor layout with directional path arrows.
class _MiniMapRadar extends StatelessWidget {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final List<MapNode> path;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final Vector3? userPosition;
  final VoidCallback onTap;

  const _MiniMapRadar({
    required this.nodes,
    required this.edges,
    required this.path,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    this.userPosition,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            CustomPaint(
              size: const Size(120, 120),
              painter: _FloorMapPainter(
                nodes: nodes,
                edges: edges,
                path: path,
                turnInstructions: turnInstructions,
                currentInstructionIndex: currentInstructionIndex,
                userPosition: userPosition,
                isMiniMap: true,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.fullscreen, color: Colors.white70, size: 12),
                    SizedBox(width: 2),
                    Text(
                      '2D',
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen 2D Floor Map View providing a clear overview with route & turn arrows.
class _FloorMapView extends StatelessWidget {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final List<MapNode> path;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final MapNode destination;
  final Vector3? userPosition;

  const _FloorMapView({
    required this.nodes,
    required this.edges,
    required this.path,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    required this.destination,
    this.userPosition,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B14),
      child: CustomPaint(
        painter: _FloorMapPainter(
          nodes: nodes,
          edges: edges,
          path: path,
          turnInstructions: turnInstructions,
          currentInstructionIndex: currentInstructionIndex,
          userPosition: userPosition,
          isMiniMap: false,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Canvas painter for 2D floor maps (both Mini-Map radar and Fullscreen 2D View).
/// Automatically normalizes coordinates and renders directional arrows along each route segment.
class _FloorMapPainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final List<MapNode> path;
  final List<TurnInstruction> turnInstructions;
  final int currentInstructionIndex;
  final Vector3? userPosition;
  final bool isMiniMap;

  _FloorMapPainter({
    required this.nodes,
    required this.edges,
    required this.path,
    required this.turnInstructions,
    required this.currentInstructionIndex,
    this.userPosition,
    required this.isMiniMap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final pad = isMiniMap ? 14.0 : 40.0;
    double minX = nodes.first.position.x;
    double maxX = nodes.first.position.x;
    double minZ = nodes.first.position.z;
    double maxZ = nodes.first.position.z;

    for (final n in nodes) {
      if (n.position.x < minX) minX = n.position.x;
      if (n.position.x > maxX) maxX = n.position.x;
      if (n.position.z < minZ) minZ = n.position.z;
      if (n.position.z > maxZ) maxZ = n.position.z;
    }

    final spanX = math.max(1.0, maxX - minX);
    final spanZ = math.max(1.0, maxZ - minZ);

    final availableW = size.width - (pad * 2);
    final availableH = size.height - (pad * 2);

    final scale = math.min(availableW / spanX, availableH / spanZ);
    final offsetX = pad + (availableW - spanX * scale) / 2 - minX * scale;
    final offsetY = pad + (availableH - spanZ * scale) / 2 - minZ * scale;

    Offset mapPoint(Position pos) =>
        Offset(offsetX + pos.x * scale, offsetY + pos.z * scale);

    final nodeMap = {for (final n in nodes) n.id: n};

    // 1. Draw floor edges (subtle)
    final edgePaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.6)
      ..strokeWidth = isMiniMap ? 1.0 : 2.0
      ..style = PaintingStyle.stroke;

    for (final e in edges) {
      final from = nodeMap[e.fromNodeId];
      final to = nodeMap[e.toNodeId];
      if (from == null || to == null) continue;
      canvas.drawLine(mapPoint(from.position), mapPoint(to.position), edgePaint);
    }

    // 2. Draw active route glow ribbon
    if (path.length >= 2) {
      final routeGlow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.3)
        ..strokeWidth = isMiniMap ? 6.0 : 10.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final routePaint = Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = isMiniMap ? 2.5 : 4.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final routePath = Path();
      routePath.moveTo(mapPoint(path.first.position).dx, mapPoint(path.first.position).dy);
      for (int i = 1; i < path.length; i++) {
        final p = mapPoint(path[i].position);
        routePath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(routePath, routeGlow);
      canvas.drawPath(routePath, routePaint);

      // 3. Draw directional arrows along each path segment
      final arrowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      for (int i = 0; i < path.length - 1; i++) {
        final p1 = mapPoint(path[i].position);
        final p2 = mapPoint(path[i + 1].position);

        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);

        canvas.save();
        canvas.translate(mid.dx, mid.dy);
        canvas.rotate(angle);

        final arrSize = isMiniMap ? 4.0 : 7.0;
        final arrow = Path();
        arrow.moveTo(arrSize * 1.2, 0);
        arrow.lineTo(-arrSize, -arrSize);
        arrow.lineTo(-arrSize * 0.4, 0);
        arrow.lineTo(-arrSize, arrSize);
        arrow.close();

        canvas.drawPath(arrow, arrowPaint);
        canvas.restore();
      }
    }

    // 4. Draw Turn instruction badges at corner junctions
    for (int i = 1; i < turnInstructions.length - 1; i++) {
      final inst = turnInstructions[i];
      final pos = Offset(
        offsetX + inst.position.x * scale,
        offsetY + inst.position.z * scale,
      );

      final lower = inst.instruction.toLowerCase();
      final isLeft = lower.contains('left');
      final isRight = lower.contains('right');

      if (isLeft || isRight) {
        final turnPaint = Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(pos, isMiniMap ? 4.0 : 7.0, turnPaint);

        if (!isMiniMap) {
          final turnText = TextSpan(
            text: isLeft ? '↰' : '↱',
            style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
          );
          final tp = TextPainter(text: turnText, textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
        }
      }
    }

    // 5. Draw start / current user node
    if (path.isNotEmpty) {
      final userCoord = userPosition != null
          ? Position(x: userPosition!.x, y: userPosition!.y, z: userPosition!.z)
          : path[currentInstructionIndex.clamp(0, path.length - 1)].position;
      final userPos = mapPoint(userCoord);

      final userRipple = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(userPos, isMiniMap ? 7.0 : 12.0, userRipple);

      final userDot = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userPos, isMiniMap ? 4.0 : 6.0, userDot);

      // Destination node
      final destPos = mapPoint(path.last.position);
      final destPaint = Paint()
        ..color = const Color(0xFFEF4444)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(destPos, isMiniMap ? 4.0 : 6.5, destPaint);

      if (!isMiniMap) {
        // Node labels
        for (final n in nodes) {
          final p = mapPoint(n.position);
          final textSpan = TextSpan(
            text: n.label,
            style: TextStyle(
              color: path.any((pn) => pn.id == n.id) ? Colors.white : Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          );
          final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 7));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FloorMapPainter oldDelegate) => true;
}
