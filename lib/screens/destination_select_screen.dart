import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/map_repository.dart';
import '../models/floor.dart';
import '../models/node.dart';
import 'navigation_screen.dart';

class DestinationSelectScreen extends StatefulWidget {
  const DestinationSelectScreen({
    super.key,
    required this.repository,
    required this.floor,
  });

  final MapRepository repository;
  final Floor floor;

  @override
  State<DestinationSelectScreen> createState() => _DestinationSelectScreenState();
}

class _DestinationSelectScreenState extends State<DestinationSelectScreen> {
  List<MapNode> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final nodes = await widget.repository.getNodes(widget.floor.id);
    setState(() {
      _rooms = nodes.where((n) => n.type == NodeType.room).toList();
      _loading = false;
    });
  }

  IconData _iconFor(NodeType type) {
    switch (type) {
      case NodeType.room:
        return CupertinoIcons.square_grid_2x2;
      case NodeType.junction:
        return CupertinoIcons.arrow_branch;
      case NodeType.stair:
        return CupertinoIcons.arrow_up_right;
      case NodeType.elevator:
        return CupertinoIcons.arrow_up_arrow_down;
      case NodeType.doorway:
        return CupertinoIcons.square_split_1x2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Select destination'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            CupertinoIcons.map,
                            size: 32,
                            color: Color(0xFF71717A),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No rooms mapped yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use Admin AR Mapping Mode to map this floor by walking and placing spatial nodes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rooms.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    final label = room.label.toLowerCase().startsWith('room')
                        ? room.label
                        : 'Room ${room.label}';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE5E5EA), width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _iconFor(room.type),
                            color: const Color(0xFF09090B),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: const Text(
                          'Tap to start AR navigation',
                          style: TextStyle(color: Color(0xFF71717A), fontSize: 12),
                        ),
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          size: 16,
                          color: Color(0xFFA1A1AA),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NavigationScreen(
                                repository: widget.repository,
                                floor: widget.floor,
                                destination: room,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
