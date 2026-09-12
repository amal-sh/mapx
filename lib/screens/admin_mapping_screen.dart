import 'dart:async';

import 'package:flutter/material.dart';

import '../data/map_repository.dart';
import '../models/building.dart';
import '../models/edge.dart';
import '../models/floor.dart';
import '../models/node.dart';
import '../native/ar_bridge.dart';
import '../native/camera_permission.dart';

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

  @override
  void initState() {
    super.initState();
    _loadExistingGraph();
    _initAr();
  }

  @override
  void dispose() {
    _arSubscription?.cancel();
    ArBridge.instance.stopMappingSession();
    super.dispose();
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
    final labelController = TextEditingController(
      text: _nodes.isEmpty ? 'Entrance' : 'Room ${101 + _nodes.length}',
    );
    NodeType selectedType = _nodes.isEmpty ? NodeType.junction : NodeType.room;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorScheme = Theme.of(context).colorScheme;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Place Spatial Node',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '(${position.x.toStringAsFixed(1)}m, ${position.z.toStringAsFixed(1)}m)',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: labelController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Node Label / Room Number',
                      hintText: 'e.g. 101, Lab 2, Main Entrance',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Node Type',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: NodeType.values.map((type) {
                      final isSelected = selectedType == type;
                      return ChoiceChip(
                        label: Text(type.name.toUpperCase()),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) setModalState(() => selectedType = type);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Confirm & Drop Node'),
                      onPressed: () {
                        final label = labelController.text.trim().isEmpty
                            ? 'Node ${_nodes.length + 1}'
                            : labelController.text.trim();
                        Navigator.of(ctx).pop();
                        _confirmDropNode(label, selectedType, position);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setInspectorState) {
            final colorScheme = Theme.of(context).colorScheme;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Floor Graph Inspector',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            '${_nodes.length} Nodes • ${_edges.length} Edges',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _nodes.isEmpty
                            ? const Center(child: Text('No nodes placed yet. Tap the AR screen to add.'))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: _nodes.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final node = _nodes[idx];
                                  final connectedEdges = _edges.where(
                                    (e) => e.fromNodeId == node.id || e.toNodeId == node.id,
                                  );

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: colorScheme.primaryContainer,
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      node.label,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      '${node.type.name} • (${node.position.x.toStringAsFixed(1)}m, ${node.position.z.toStringAsFixed(1)}m) • ${connectedEdges.length} links',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.link,
                                            color: _linkSourceNode?.id == node.id
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                          onPressed: () {
                                            Navigator.of(ctx).pop();
                                            setState(() => _isLinkingMode = true);
                                            _startManualLink(node);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          onPressed: () {
                                            _deleteNode(node);
                                            setInspectorState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
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
              label: Text('${_nodes.length}'),
              child: const Icon(Icons.account_tree_outlined),
            ),
            onPressed: _showInspector,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.tonal(
              onPressed: _nodes.isEmpty ? null : _saveAndExit,
              child: const Text('Save'),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
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
                    Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Clear Floor Map', style: TextStyle(color: Colors.red)),
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
                    // AR Viewfinder & Hit-Test Surface
                    GestureDetector(
                      onTapUp: (details) => _handleViewportTap(details, constraints),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFF0F172A), // Dark slate viewport
                        child: CustomPaint(
                          painter: _GridPainter(
                            nodes: _nodes,
                            edges: _edges,
                            selectedNode: _linkSourceNode,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isLinkingMode ? Icons.touch_app : Icons.add_circle_outline,
                                  color: Colors.white24,
                                  size: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _isLinkingMode
                                      ? 'Tap any node in inspector to link'
                                      : 'Tap surface to drop a spatial node',
                                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.link, color: colorScheme.onPrimaryContainer),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _linkSourceNode == null
                                      ? 'Select first node to connect'
                                      : 'Selected "${_linkSourceNode!.label}". Select second node.',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
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
                      child: Card(
                        color: Colors.black.withValues(alpha: 0.85),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Colors.white12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                icon: const Icon(Icons.add_location_alt_outlined),
                                label: const Text('Add Node'),
                                onPressed: () {
                                  _showAddNodeDialog(
                                    Position(
                                      x: (_nodes.length * 2.5),
                                      y: 0,
                                      z: 0,
                                    ),
                                  );
                                },
                              ),
                              Container(height: 24, width: 1, color: Colors.white24),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: _isLinkingMode ? colorScheme.primary : Colors.white,
                                ),
                                icon: const Icon(Icons.polyline_outlined),
                                label: const Text('Link Edge'),
                                onPressed: _nodes.length < 2
                                    ? null
                                    : () {
                                        setState(() => _isLinkingMode = !_isLinkingMode);
                                        _showInspector();
                                      },
                              ),
                              Container(height: 24, width: 1, color: Colors.white24),
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                icon: const Icon(Icons.list_alt),
                                label: Text('${_nodes.length} Nodes'),
                                onPressed: _showInspector,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// Canvas painter that visualizes placed nodes and connected edges in real time.
class _GridPainter extends CustomPainter {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final MapNode? selectedNode;

  _GridPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const scale = 25.0; // Pixels per meter

    final linePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final nodeMap = {for (final n in nodes) n.id: n};

    // Draw Edges
    for (final edge in edges) {
      final from = nodeMap[edge.fromNodeId];
      final to = nodeMap[edge.toNodeId];
      if (from == null || to == null) continue;

      final p1 = Offset(centerX + from.position.x * scale, centerY + from.position.z * scale);
      final p2 = Offset(centerX + to.position.x * scale, centerY + to.position.z * scale);

      canvas.drawLine(p1, p2, linePaint);
    }

    // Draw Nodes
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final isSelected = selectedNode?.id == node.id;
      final offset = Offset(centerX + node.position.x * scale, centerY + node.position.z * scale);

      final nodePaint = Paint()
        ..color = isSelected
            ? const Color(0xFFF59E0B)
            : (node.type == NodeType.room ? const Color(0xFF2563EB) : const Color(0xFF10B981))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(offset, isSelected ? 9.0 : 6.5, nodePaint);

      // Label text
      final textSpan = TextSpan(
        text: node.label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(offset.dx - textPainter.width / 2, offset.dy + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}
