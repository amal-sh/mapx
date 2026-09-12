import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/map_repository.dart';
import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';
import '../native/ar_bridge.dart';
import '../native/camera_permission.dart';
import '../widgets/mapping/grid_painter.dart';
import '../widgets/mapping/mapping_controls_bar.dart';
import '../widgets/mapping/mapping_inspector_sheet.dart';
import '../widgets/mapping/node_form_dialog.dart';

/// In-app AR Mapping tool for building administrators.
///
/// Features Combined Mode:
/// - Auto-breadcrumb mode: Walking and placing nodes automatically creates
///   weighted edges with real Euclidean distance.
/// - Manual linking: Select any two nodes to form custom cross-corridor edges.
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

class _AdminMappingScreenState extends State<AdminMappingScreen> {
  final List<MapNode> _nodes = [];
  final List<MapEdge> _edges = [];

  bool _loading = true;
  bool _mappingSessionActive = false;
  bool _breadcrumbMode = true;
  MapNode? _lastPlacedNode;
  MapNode? _linkSourceNode;
  bool _isLinkingMode = false;
  int _planeCount = 0;
  StreamSubscription<ArEvent>? _arSubscription;

  CameraController? _cameraController;
  bool _cameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadExistingGraph();
    _initAr();
    _initCamera();
  }

  @override
  void dispose() {
    _arSubscription?.cancel();
    _cameraController?.dispose();
    ArBridge.instance.stopMappingSession();
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

  Future<void> _loadExistingGraph() async {
    final existingNodes = await widget.repository.getNodes(widget.floor.id);
    final existingEdges = await widget.repository.getEdges(widget.floor.id);

    if (mounted) {
      setState(() {
        _nodes.addAll(existingNodes);
        _edges.addAll(existingEdges);
        if (_nodes.isNotEmpty) {
          _lastPlacedNode = _nodes.last;
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
      }
    });
  }

  Future<void> _handleViewportTap(TapUpDetails details, BoxConstraints constraints) async {
    if (_isLinkingMode) return;

    final screenX = details.localPosition.dx / constraints.maxWidth;
    final screenY = details.localPosition.dy / constraints.maxHeight;

    final hit = await ArBridge.instance.hitTest(screenX, screenY);
    final position = hit != null
        ? Position(x: hit.x, y: hit.y, z: hit.z)
        : Position(
            x: ((screenX - 0.5) * 10).roundToDouble(),
            y: 0.0,
            z: (screenY * 8).roundToDouble(),
          );

    if (!mounted) return;
    _showAddNodeDialog(position);
  }

  void _showAddNodeDialog(Position position) {
    NodeFormDialog.show(
      context: context,
      position: position,
      suggestedLabel: _nodes.isEmpty ? 'Entrance' : 'Room ${101 + _nodes.length}',
      initialType: _nodes.isEmpty ? NodeType.junction : NodeType.room,
      onConfirm: (label, type) {
        _confirmDropNode(label, type, position);
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

      // Auto-Breadcrumb linking: automatically connect to previously placed node
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
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _breadcrumbMode && _nodes.length > 1
              ? 'Placed "$label" & auto-linked to "${_nodes[_nodes.length - 2].label}"'
              : 'Placed spatial node "$label"',
        ),
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
      }
    });
  }

  Future<void> _saveAndExit() async {
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
                    // AR Live Camera Viewfinder & Hit-Test Surface
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
                          else
                            Container(color: const Color(0xFF09090B)),

                          GestureDetector(
                            onTapUp: (details) => _handleViewportTap(details, constraints),
                            child: CustomPaint(
                              painter: GridPainter(
                                nodes: _nodes,
                                edges: _edges,
                                selectedNode: _linkSourceNode,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isLinkingMode ? CupertinoIcons.hand_point_right : CupertinoIcons.plus_circle,
                                      color: Colors.white70,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Text(
                                        _isLinkingMode
                                            ? 'Tap any node in inspector to link'
                                            : 'Point camera at floor & tap to drop node',
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Top Status HUD
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
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
                                    color: _mappingSessionActive ? Colors.greenAccent : Colors.amberAccent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _mappingSessionActive
                                      ? 'AR Surface Active ($_planeCount)'
                                      : 'AR Initializing...',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Breadcrumb mode toggle
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
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

                    // Linking Mode Banner
                    if (_isLinkingMode)
                      Positioned(
                        top: 70,
                        left: 16,
                        right: 16,
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

                    // Bottom Floating Action Toolbar
                    Positioned(
                      bottom: 24,
                      left: 20,
                      right: 20,
                      child: MappingControlsBar(
                        nodeCount: _nodes.length,
                        isLinkingMode: _isLinkingMode,
                        onAddNode: () {
                          _showAddNodeDialog(
                            Position(
                              x: (_nodes.length * 2.5),
                              y: 0,
                              z: 0,
                            ),
                          );
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
