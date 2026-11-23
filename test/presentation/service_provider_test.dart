import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/presentation/providers/service_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ServicePositionStorage', () {
    test('saves, retrieves, and clears last position per playlist', () async {
      final storage = ServicePositionStorage();

      // Default is 0 when no position was saved
      final initial = await storage.getSavedPosition(101);
      expect(initial, 0);

      // Save position 3 for playlist 101
      await storage.savePosition(101, 3);
      final saved = await storage.getSavedPosition(101);
      expect(saved, 3);

      // Other playlists remain at 0
      final other = await storage.getSavedPosition(102);
      expect(other, 0);

      // Clear position
      await storage.clearPosition(101);
      final afterClear = await storage.getSavedPosition(101);
      expect(afterClear, 0);
    });
  });

  group('ServiceController', () {
    final mockItems = [
      PlaylistItemWithSong(
        item: const PlaylistItem(
          id: 1,
          playlistId: 10,
          songId: 100,
          position: 0,
        ),
        song: Song(
          id: 100,
          title: 'Song A',
          url: 'https://tabs.ultimate-guitar.com/tab/a/1',
          createdAt: DateTime(2026, 1, 1),
          archived: false,
        ),
      ),
      PlaylistItemWithSong(
        item: const PlaylistItem(
          id: 2,
          playlistId: 10,
          songId: 200,
          position: 1,
        ),
        song: Song(
          id: 200,
          title: 'Song B',
          url: 'https://tabs.ultimate-guitar.com/tab/b/2',
          createdAt: DateTime(2026, 1, 1),
          archived: false,
        ),
      ),
      PlaylistItemWithSong(
        item: const PlaylistItem(
          id: 3,
          playlistId: 10,
          songId: 300,
          position: 2,
        ),
        song: Song(
          id: 300,
          title: 'Song C',
          url: 'https://tabs.ultimate-guitar.com/tab/c/3',
          createdAt: DateTime(2026, 1, 1),
          archived: false,
        ),
      ),
    ];

    test('navigation next, previous, jumpTo, and bounds checking', () {
      final storage = ServicePositionStorage();
      final controller = ServiceController(
        playlistId: 10,
        initialItems: mockItems,
        initialIndex: 0,
        storage: storage,
      );

      expect(controller.state.currentIndex, 0);
      expect(controller.state.canGoPrevious, isFalse);
      expect(controller.state.canGoNext, isTrue);
      expect(controller.state.currentItem?.song.title, 'Song A');

      // Next
      controller.next();
      expect(controller.state.currentIndex, 1);
      expect(controller.state.canGoPrevious, isTrue);
      expect(controller.state.canGoNext, isTrue);

      // Next to last
      controller.next();
      expect(controller.state.currentIndex, 2);
      expect(controller.state.canGoPrevious, isTrue);
      expect(controller.state.canGoNext, isFalse);

      // Next at boundary does nothing
      controller.next();
      expect(controller.state.currentIndex, 2);

      // Jump to 0
      controller.jumpTo(0);
      expect(controller.state.currentIndex, 0);

      // Previous at boundary does nothing
      controller.previous();
      expect(controller.state.currentIndex, 0);
    });

    test('notes panel collapse and expansion toggle', () {
      final storage = ServicePositionStorage();
      final controller = ServiceController(
        playlistId: 10,
        initialItems: mockItems,
        initialIndex: 0,
        storage: storage,
      );

      expect(controller.state.isNotesExpanded, isFalse);
      controller.toggleNotes();
      expect(controller.state.isNotesExpanded, isTrue);
      controller.toggleNotes();
      expect(controller.state.isNotesExpanded, isFalse);
    });
  });
}
