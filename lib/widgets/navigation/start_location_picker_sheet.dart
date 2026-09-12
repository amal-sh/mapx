import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/node.dart';

/// Modal Bottom Sheet for selecting the Current Starting Location
/// Designed with a minimal monochrome aesthetic matching [AppTheme].
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
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
    if (lower.contains('entrance')) return CupertinoIcons.arrow_right_circle;
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

  String _typeLabel(MapNode node) {
    if (node.label.toLowerCase().contains('entrance')) return 'Entrance';
    switch (node.type) {
      case NodeType.room:
        return 'Room';
      case NodeType.stair:
        return 'Stairs';
      case NodeType.elevator:
        return 'Elevator';
      case NodeType.junction:
        return 'Hallway Junction';
      case NodeType.doorway:
        return 'Doorway';
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4D4D8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        CupertinoIcons.location_north_fill,
                        color: Color(0xFF09090B),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Start Location',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: Color(0xFF09090B),
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.floorName} • To ${widget.destination.label}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: Color(0xFF71717A),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF4F4F5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          color: Color(0xFF71717A),
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // OCR Doorplate Auto-Detect Button (Minimal Monochrome Card)
              if (widget.onScanRequested != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: InkWell(
                    onTap: widget.onScanRequested,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09090B),
                        borderRadius: BorderRadius.circular(14),
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
                                  'Scan Room Doorplate (OCR)',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Point camera at room number to auto-detect start',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Color(0xFFA1A1AA),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(CupertinoIcons.chevron_right, color: Color(0xFFA1A1AA), size: 14),
                        ],
                      ),
                    ),
                  ),
                ),

              // Search Field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Color(0xFF09090B),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search rooms, entrances, stairs...',
                      hintStyle: const TextStyle(
                        fontFamily: 'Inter',
                        color: Color(0xFF71717A),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(CupertinoIcons.search, color: Color(0xFF71717A), size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(CupertinoIcons.clear_circled_solid, color: Color(0xFF71717A), size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
              ),

              // Category Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    _buildCategoryChip('All Locations', 'all'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Entrances', 'entrance'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Rooms', 'room'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('Stairs & Lifts', 'transit'),
                  ],
                ),
              ),

              const SizedBox(height: 4),
              const Divider(color: Color(0xFFE5E5EA), height: 1),

              // Nodes List
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.search, size: 36, color: Color(0xFFA1A1AA)),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty ? 'No locations available' : 'No matches for "$_searchQuery"',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: Color(0xFF71717A),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final node = filtered[index];
                          final isSelected = widget.selectedNode?.id == node.id;
                          final typeIcon = _iconForType(node.type, node.label);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => widget.onNodeSelected(node),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFFAFAFA) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF09090B) : const Color(0xFFE5E5EA),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF09090B) : const Color(0xFFF4F4F5),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        typeIcon,
                                        color: isSelected ? Colors.white : const Color(0xFF27272A),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            node.label,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              color: const Color(0xFF09090B),
                                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                              fontSize: 14,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_typeLabel(node)} • (${node.position.x.toStringAsFixed(1)}, ${node.position.z.toStringAsFixed(1)})',
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              color: Color(0xFF71717A),
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
                                          color: const Color(0xFF09090B),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'START',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      )
                                    else
                                      const Icon(
                                        CupertinoIcons.chevron_right,
                                        color: Color(0xFFA1A1AA),
                                        size: 14,
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
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String categoryKey) {
    final isSelected = _selectedCategory == categoryKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = categoryKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF09090B) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF09090B) : const Color(0xFFE4E4E7),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            color: isSelected ? Colors.white : const Color(0xFF52525B),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
