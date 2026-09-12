import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/edge.dart';
import '../../models/node.dart';

class MappingInspectorSheet extends StatelessWidget {
  const MappingInspectorSheet({
    super.key,
    required this.nodes,
    required this.edges,
    required this.linkSourceNode,
    required this.onStartLink,
    required this.onDeleteNode,
  });

  final List<MapNode> nodes;
  final List<MapEdge> edges;
  final MapNode? linkSourceNode;
  final ValueChanged<MapNode> onStartLink;
  final ValueChanged<MapNode> onDeleteNode;

  static void show({
    required BuildContext context,
    required List<MapNode> nodes,
    required List<MapEdge> edges,
    required MapNode? linkSourceNode,
    required ValueChanged<MapNode> onStartLink,
    required ValueChanged<MapNode> onDeleteNode,
  }) {
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
            return MappingInspectorSheet(
              nodes: nodes,
              edges: edges,
              linkSourceNode: linkSourceNode,
              onStartLink: (node) {
                Navigator.of(ctx).pop();
                onStartLink(node);
              },
              onDeleteNode: (node) {
                onDeleteNode(node);
                setInspectorState(() {});
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
                    '${nodes.length} Nodes • ${edges.length} Edges',
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
                child: nodes.isEmpty
                    ? const Center(
                        child: Text('No nodes placed yet. Tap the AR screen to add.'),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: nodes.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final node = nodes[idx];
                          final connectedEdges = edges.where(
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
                                    CupertinoIcons.link,
                                    size: 20,
                                    color: linkSourceNode?.id == node.id
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  onPressed: () => onStartLink(node),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    CupertinoIcons.trash,
                                    size: 18,
                                    color: Color(0xFFDC2626),
                                  ),
                                  onPressed: () => onDeleteNode(node),
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
  }
}
