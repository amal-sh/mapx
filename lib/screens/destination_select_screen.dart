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
        return Icons.meeting_room_outlined;
      case NodeType.junction:
        return Icons.call_split;
      case NodeType.stair:
        return Icons.stairs_outlined;
      case NodeType.elevator:
        return Icons.elevator_outlined;
      case NodeType.doorway:
        return Icons.door_front_door_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select destination')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        _iconFor(room.type),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text('Room ${room.label}'),
                    trailing: const Icon(Icons.chevron_right),
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
