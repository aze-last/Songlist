import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/domain/playlist_order.dart';

void main() {
  group('PlaylistItemOrder', () {
    test('renormalize assigns contiguous 0..n-1 positions', () {
      final items = [
        const OrderedItem(id: 1, songId: 10, position: 5),
        const OrderedItem(id: 2, songId: 20, position: 10),
        const OrderedItem(id: 3, songId: 30, position: 1),
      ];

      // After sorting by existing position and renormalizing:
      final normalized = PlaylistOrderManager.renormalize(items);
      expect(normalized.length, 3);
      expect(normalized[0].id, 3);
      expect(normalized[0].position, 0);
      expect(normalized[1].id, 1);
      expect(normalized[1].position, 1);
      expect(normalized[2].id, 2);
      expect(normalized[2].position, 2);
    });

    test('addItem places new item at contiguous end position', () {
      final items = [
        const OrderedItem(id: 1, songId: 10, position: 0),
        const OrderedItem(id: 2, songId: 20, position: 1),
      ];

      final updated = PlaylistOrderManager.addItem(
        items,
        const OrderedItem(id: 3, songId: 30, position: -1),
      );

      expect(updated.length, 3);
      expect(updated.map((i) => i.position).toList(), [0, 1, 2]);
      expect(updated.last.songId, 30);
    });

    test('permits duplicate song IDs in the same playlist with unique item IDs and positions', () {
      final items = [const OrderedItem(id: 1, songId: 10, position: 0)];

      final updated = PlaylistOrderManager.addItem(
        items,
        const OrderedItem(id: 2, songId: 10, position: -1),
      );

      expect(updated.length, 2);
      expect(updated[0].songId, 10);
      expect(updated[0].position, 0);
      expect(updated[1].songId, 10);
      expect(updated[1].position, 1);
    });

    test('removeItem removes target and renormalizes remaining items', () {
      final items = [
        const OrderedItem(id: 1, songId: 10, position: 0),
        const OrderedItem(id: 2, songId: 20, position: 1),
        const OrderedItem(id: 3, songId: 30, position: 2),
      ];

      final updated = PlaylistOrderManager.removeItem(items, itemId: 2);
      expect(updated.length, 2);
      expect(updated[0].id, 1);
      expect(updated[0].position, 0);
      expect(updated[1].id, 3);
      expect(updated[1].position, 1);
    });

    test(
      'moveItem moves an item from oldIndex to newIndex and renormalizes',
      () {
        final items = [
          const OrderedItem(id: 1, songId: 10, position: 0),
          const OrderedItem(id: 2, songId: 20, position: 1),
          const OrderedItem(id: 3, songId: 30, position: 2),
        ];

        // Move item at index 0 to index 2 (to end)
        final movedToEnd = PlaylistOrderManager.moveItem(
          items,
          oldIndex: 0,
          newIndex: 2,
        );
        expect(movedToEnd.map((i) => i.id).toList(), [2, 3, 1]);
        expect(movedToEnd.map((i) => i.position).toList(), [0, 1, 2]);

        // Move item at index 2 to index 0 (to start)
        final movedToStart = PlaylistOrderManager.moveItem(
          movedToEnd,
          oldIndex: 2,
          newIndex: 0,
        );
        expect(movedToStart.map((i) => i.id).toList(), [1, 2, 3]);
        expect(movedToStart.map((i) => i.position).toList(), [0, 1, 2]);
      },
    );

    test('moveUp and moveDown shift positions with boundary safety', () {
      final items = [
        const OrderedItem(id: 1, songId: 10, position: 0),
        const OrderedItem(id: 2, songId: 20, position: 1),
      ];

      // Moving first item up does nothing
      final upAtTop = PlaylistOrderManager.moveUp(items, index: 0);
      expect(upAtTop.map((i) => i.id).toList(), [1, 2]);

      // Moving second item up swaps with first
      final upSecond = PlaylistOrderManager.moveUp(items, index: 1);
      expect(upSecond.map((i) => i.id).toList(), [2, 1]);

      // Moving last item down does nothing
      final downAtBottom = PlaylistOrderManager.moveDown(items, index: 1);
      expect(downAtBottom.map((i) => i.id).toList(), [1, 2]);

      // Moving first item down swaps with second
      final downFirst = PlaylistOrderManager.moveDown(items, index: 0);
      expect(downFirst.map((i) => i.id).toList(), [2, 1]);
    });

    test('service navigation bounds and resume position validation', () {
      // Empty playlist
      expect(
        PlaylistOrderManager.canGoPrevious(currentIndex: 0, totalItems: 0),
        isFalse,
      );
      expect(
        PlaylistOrderManager.canGoNext(currentIndex: 0, totalItems: 0),
        isFalse,
      );
      expect(
        PlaylistOrderManager.clampResumePosition(
          savedPosition: 2,
          totalItems: 0,
        ),
        0,
      );

      // Single item
      expect(
        PlaylistOrderManager.canGoPrevious(currentIndex: 0, totalItems: 1),
        isFalse,
      );
      expect(
        PlaylistOrderManager.canGoNext(currentIndex: 0, totalItems: 1),
        isFalse,
      );

      // 3 items
      expect(
        PlaylistOrderManager.canGoPrevious(currentIndex: 0, totalItems: 3),
        isFalse,
      );
      expect(
        PlaylistOrderManager.canGoNext(currentIndex: 0, totalItems: 3),
        isTrue,
      );

      expect(
        PlaylistOrderManager.canGoPrevious(currentIndex: 1, totalItems: 3),
        isTrue,
      );
      expect(
        PlaylistOrderManager.canGoNext(currentIndex: 1, totalItems: 3),
        isTrue,
      );

      expect(
        PlaylistOrderManager.canGoPrevious(currentIndex: 2, totalItems: 3),
        isTrue,
      );
      expect(
        PlaylistOrderManager.canGoNext(currentIndex: 2, totalItems: 3),
        isFalse,
      );

      // Clamping resume position
      expect(
        PlaylistOrderManager.clampResumePosition(
          savedPosition: -1,
          totalItems: 3,
        ),
        0,
      );
      expect(
        PlaylistOrderManager.clampResumePosition(
          savedPosition: 1,
          totalItems: 3,
        ),
        1,
      );
      expect(
        PlaylistOrderManager.clampResumePosition(
          savedPosition: 5,
          totalItems: 3,
        ),
        2,
      );
    });
  });
}
