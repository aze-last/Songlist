/// Pure Dart domain model and ordering logic for playlist items.
///
/// Complies with spec.md Sections 4, 5.2, 5.3, and 10:
/// - Contiguous 0..n-1 positions per playlist.
/// - Automatic position renormalization on addition, removal, or reordering.
/// - Duplicate song entries permitted in the same playlist.
/// - Bounds checking for Previous/Next navigation in Service Mode.
/// - Resume position clamping.
class OrderedItem {
  final int id;
  final int songId;
  final int position;

  const OrderedItem({
    required this.id,
    required this.songId,
    required this.position,
  });

  OrderedItem copyWith({int? id, int? songId, int? position}) {
    return OrderedItem(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderedItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          songId == other.songId &&
          position == other.position;

  @override
  int get hashCode => id.hashCode ^ songId.hashCode ^ position.hashCode;

  @override
  String toString() =>
      'OrderedItem(id: $id, songId: $songId, position: $position)';
}

class PlaylistOrderManager {
  /// Sorts items by their current position and renormalizes positions to 0..n-1.
  static List<OrderedItem> renormalize(List<OrderedItem> items) {
    final sorted = List<OrderedItem>.from(items)
      ..sort((a, b) => a.position.compareTo(b.position));

    return List.generate(
      sorted.length,
      (index) => sorted[index].copyWith(position: index),
    );
  }

  /// Appends a new item at the end of the playlist with position n.
  static List<OrderedItem> addItem(
    List<OrderedItem> currentItems,
    OrderedItem newItem,
  ) {
    final normalized = renormalize(currentItems);
    return [...normalized, newItem.copyWith(position: normalized.length)];
  }

  /// Removes an item by its unique item ID and renormalizes remaining items.
  static List<OrderedItem> removeItem(
    List<OrderedItem> currentItems, {
    required int itemId,
  }) {
    final remaining = currentItems.where((item) => item.id != itemId).toList();
    return renormalize(remaining);
  }

  /// Moves an item from oldIndex to newIndex and renormalizes all positions.
  static List<OrderedItem> moveItem(
    List<OrderedItem> currentItems, {
    required int oldIndex,
    required int newIndex,
  }) {
    final list = List<OrderedItem>.from(renormalize(currentItems));
    if (oldIndex < 0 ||
        oldIndex >= list.length ||
        newIndex < 0 ||
        newIndex >= list.length ||
        oldIndex == newIndex) {
      return list;
    }

    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    return List.generate(list.length, (i) => list[i].copyWith(position: i));
  }

  /// Moves an item up (towards 0). If already at 0, returns current list.
  static List<OrderedItem> moveUp(
    List<OrderedItem> currentItems, {
    required int index,
  }) {
    if (index <= 0) return currentItems;
    return moveItem(currentItems, oldIndex: index, newIndex: index - 1);
  }

  /// Moves an item down (towards n-1). If already at n-1, returns current list.
  static List<OrderedItem> moveDown(
    List<OrderedItem> currentItems, {
    required int index,
  }) {
    if (index >= currentItems.length - 1) return currentItems;
    return moveItem(currentItems, oldIndex: index, newIndex: index + 1);
  }

  /// Navigation bound: Previous button is enabled only when currentIndex > 0.
  static bool canGoPrevious({
    required int currentIndex,
    required int totalItems,
  }) {
    if (totalItems <= 1) return false;
    return currentIndex > 0;
  }

  /// Navigation bound: Next button is enabled only when currentIndex < totalItems - 1.
  static bool canGoNext({required int currentIndex, required int totalItems}) {
    if (totalItems <= 1) return false;
    return currentIndex < totalItems - 1;
  }

  /// Clamps saved position so it always falls into [0, totalItems - 1].
  static int clampResumePosition({
    required int savedPosition,
    required int totalItems,
  }) {
    if (totalItems <= 0) return 0;
    if (savedPosition < 0) return 0;
    if (savedPosition >= totalItems) return totalItems - 1;
    return savedPosition;
  }
}
