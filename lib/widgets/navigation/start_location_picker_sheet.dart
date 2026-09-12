import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/node.dart';

/// Modal Bottom Sheet for selecting the Current Starting Location
class StartLocationPickerSheet extends StatefulWidget {
  final List<MapNode> nodes;
  final MapNode destination;
  final MapNode? selectedNode;
  final String floorName;
  final ValueChanged<MapNode> onNodeSelected;
  final VoidCallback? onScanRequested;

  const StartLocationPickerSheet({
    super.key,
    required this.nodes,
    required this.destination,
    required this.selectedNode,
    required this.floorName,
    required this.onNodeSelected,
    this.onScanRequested,
  });

  static void show({
    required BuildContext context,
    required List<MapNode> nodes,
    required MapNode destination,
    required MapNode? selectedNode,
    required String floorName,
    required ValueChanged<MapNode> onNodeSelected,
    VoidCallback? onScanRequested,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StartLocationPickerSheet(
        nodes: nodes,
        destination: destination,
        selectedNode: selectedNode,
        floorName: floorName,
        onScanRequested: onScanRequested != null
            ? () {
                Navigator.of(ctx).pop();
                onScanRequested();
              }
            : null,
        onNodeSelected: (node) {
          Navigator.of(ctx).pop();
          onNodeSelected(node);
        },
      ),
    );
  }

  @override
  State<StartLocationPickerSheet> createState() => _StartLocationPickerSheetState();
}

class _StartLocationPickerSheetState extends State<StartLocationPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all'; // 'all', 'entrance', 'room', 'transit'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _iconForType(NodeType type, String label) {
    final lower = label.toLowerCase();
    if (lower.contains('entrance')) return CupertinoIcons.arrow_right_circle_fill;
    switch (type) {
      case NodeType.room:
        return CupertinoIcons.square_grid_2x2_fill;
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

  Color _colorForType(NodeType type, String label) {
    final lower = label.toLowerCase();
    if (lower.contains('entrance')) return const Color(0xFF10B981); // Emerald
    switch (type) {
      case NodeType.room:
        return const Color(0xFF38BDF8); // Cyan / Blue
      case NodeType.stair:
      case NodeType.elevator:
        return const Color(0xFFF59E0B); // Amber
      case NodeType.junction:
      case NodeType.doorway:
        return const Color(0xFFA855F7); // Purple
    }
  }

  List<MapNode> get _filteredNodes {
    return widget.nodes.where((node) {
      // Cannot start at the target destination itself
      if (node.id == widget.destination.id) return false;

      // Category filter
      if (_selectedCategory == 'entrance') {
        if (!node.label.toLowerCase().contains('entrance')) return false;
      } else if (_selectedCategory == 'room') {
        if (node.type != NodeType.room) return false;
      } else if (_selectedCategory == 'transit') {
        if (node.type != NodeType.stair && node.type != NodeType.elevator && node.type != NodeType.junction) {
          return false;
        }
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesLabel = node.label.toLowerCase().contains(q);
        final matchesId = node.id.toLowerCase().contains(q);
        final matchesType = node.type.name.toLowerCase().contains(q);
        return matchesLabel || matchesId || matchesType;
      }

      return true;
    }).toList()
      ..sort((a, b) {
        // Entrance first
        final aIsEnt = a.label.toLowerCase().contains('entrance') ? 0 : 1;
        final bIsEnt = b.label.toLowerCase().contains('entrance') ? 0 : 1;
        if (aIsEnt != bIsEnt) return aIsEnt.compareTo(bIsEnt);
        return a.label.compareTo(b.label);
      });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNodes;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white24, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.location_fill, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Current Location',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.floorName} • Navigating to ${widget.destination.label}',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white38, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // OCR Doorplate Auto-Detect Button
          if (widget.onScanRequested != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: InkWell(
                onTap: widget.onScanRequested,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF0F766E)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.viewfinder, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-Detect via Doorplate (OCR)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Point camera at room number to set start location',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(CupertinoIcons.chevron_right, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ),
            ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search rooms, entrance, stairs...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(CupertinoIcons.search, color: Colors.white54, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(CupertinoIcons.clear_circled_solid, color: Colors.white54, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                _buildCategoryChip('All Locations', 'all'),
                const SizedBox(width: 8),
                _buildCategoryChip('🚪 Entrances', 'entrance'),
                const SizedBox(width: 8),
                _buildCategoryChip('🏢 Rooms', 'room'),
                const SizedBox(width: 8),
                _buildCategoryChip('🪜 Stairs & Lifts', 'transit'),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Nodes List
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.search, size: 36, color: Colors.white24),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isEmpty ? 'No locations available' : 'No matches for "$_searchQuery"',
                          style: const TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final node = filtered[index];
                      final isSelected = widget.selectedNode?.id == node.id;
                      final typeColor = _colorForType(node.type, node.label);
                      final typeIcon = _iconForType(node.type, node.label);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => widget.onNodeSelected(node),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : const Color(0xFF1E293B).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF10B981) : Colors.white10,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(typeIcon, color: typeColor, size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        node.label,
                                        style: TextStyle(
                                          color: isSelected ? const Color(0xFF34D399) : Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${node.type.name.toUpperCase()} • Pos: (${node.position.x.toStringAsFixed(1)}, ${node.position.z.toStringAsFixed(1)})',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'CURRENT',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else
                                  const Icon(
                                    CupertinoIcons.chevron_right,
                                    color: Colors.white30,
                                    size: 16,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String categoryKey) {
    final isSelected = _selectedCategory == categoryKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = categoryKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
