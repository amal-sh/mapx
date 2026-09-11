import 'package:flutter/material.dart';

import '../data/map_repository.dart';
import '../logic/pathfinder.dart';
import '../models/floor.dart';
import '../models/node.dart';
import '../native/ar_bridge.dart';
import '../native/camera_permission.dart';

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

class _NavigationScreenState extends State<NavigationScreen> {
  List<MapNode> _path = [];
  bool _loading = true;
  bool _arSessionActive = false;
  bool? _cameraGranted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Fire-and-forget: nothing to await from dispose(), and there's no
    // native session to tear down yet if this never got one (non-Android
    // dev builds, or the native side hasn't started ARCore for real yet).
    ArBridge.instance.stopArSession().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _load() async {
    final nodes = await widget.repository.getNodes(widget.floor.id);
    final edges = await widget.repository.getEdges(widget.floor.id);

    // TODO(Phase 2): starting node should come from OCR + AR hit-test
    // localization instead of being assumed as the floor entrance.
    final path = findPath(
      nodes: nodes,
      edges: edges,
      startNodeId: 'entrance',
      endNodeId: widget.destination.id,
    );

    setState(() {
      _path = path;
      _loading = false;
    });

    // ARCore needs the runtime CAMERA permission granted before a Session
    // can be created — the manifest entry alone doesn't get us this.
    final granted = await ensureCameraPermission();
    if (mounted) setState(() => _cameraGranted = granted);
    if (!granted) return;

    // Exercises the Method Channel contract now, even though the native
    // side is still a stub (see android/.../ArBridge.kt). Swallowed on
    // platforms with no native AR bridge registered (web/desktop dev runs).
    try {
      final started = await ArBridge.instance.startArSession(widget.floor.id);
      if (mounted) setState(() => _arSessionActive = started);
    } catch (_) {
      // No native AR bridge on this platform — expected outside Android.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('To Room ${widget.destination.label}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // TODO(Phase 4): replace with the native SceneView AR camera
                // feed (via Method/Event Channel) rendering Bezier-smoothed
                // path arrows anchored in real-world space.
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_outlined, color: Colors.white38, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'AR camera preview',
                          style: TextStyle(color: Colors.white60, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Arrives in Phase 4 (native ARCore + SceneView)',
                          style: TextStyle(color: Colors.white30, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _cameraGranted == false
                              ? 'AR bridge: camera permission denied'
                              : _arSessionActive
                                  ? 'AR bridge: session ack received'
                                  : 'AR bridge: no native handler (non-Android build)',
                          style: const TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _path.isEmpty
                      ? const Center(child: Text('No route found'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _path.length,
                          itemBuilder: (context, index) {
                            final node = _path[index];
                            final isFirst = index == 0;
                            final isLast = index == _path.length - 1;
                            return Row(
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isLast
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant,
                                      ),
                                    ),
                                    if (!isLast)
                                      Container(
                                        width: 2,
                                        height: 28,
                                        color: colorScheme.outlineVariant,
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: Text(
                                      isFirst
                                          ? 'Start: ${node.label}'
                                          : isLast
                                              ? 'Arrive: ${node.label}'
                                              : node.label,
                                      style: TextStyle(
                                        fontWeight:
                                            isLast ? FontWeight.w700 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
