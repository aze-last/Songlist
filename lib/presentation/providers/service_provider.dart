import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/playlist_order.dart';

/// Storage helper for remembering the last viewed song position per playlist (spec.md Section 5.3).
class ServicePositionStorage {
  static const String _keyPrefix = 'playlist_last_pos_';

  Future<int> getSavedPosition(int playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_keyPrefix$playlistId') ?? 0;
  }

  Future<void> savePosition(int playlistId, int position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_keyPrefix$playlistId', position);
  }

  Future<void> clearPosition(int playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$playlistId');
  }
}

final servicePositionStorageProvider = Provider<ServicePositionStorage>(
  (ref) => ServicePositionStorage(),
);

/// Immutable state representing active Service Mode.
class ServiceState {
  final int playlistId;
  final List<PlaylistItemWithSong> items;
  final int currentIndex;
  final bool isNotesExpanded;

  const ServiceState({
    required this.playlistId,
    required this.items,
    required this.currentIndex,
    this.isNotesExpanded = false,
  });

  PlaylistItemWithSong? get currentItem =>
      (items.isNotEmpty && currentIndex >= 0 && currentIndex < items.length)
      ? items[currentIndex]
      : null;

  bool get canGoPrevious => PlaylistOrderManager.canGoPrevious(
    currentIndex: currentIndex,
    totalItems: items.length,
  );

  bool get canGoNext => PlaylistOrderManager.canGoNext(
    currentIndex: currentIndex,
    totalItems: items.length,
  );

  ServiceState copyWith({
    int? currentIndex,
    bool? isNotesExpanded,
    List<PlaylistItemWithSong>? items,
  }) {
    return ServiceState(
      playlistId: playlistId,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      isNotesExpanded: isNotesExpanded ?? this.isNotesExpanded,
    );
  }
}

/// Controller managing Service Mode active state, navigation, and position persistence.
class ServiceController extends ChangeNotifier {
  final ServicePositionStorage _storage;
  late ServiceState _state;

  ServiceController({
    required int playlistId,
    required List<PlaylistItemWithSong> initialItems,
    required int initialIndex,
    ServicePositionStorage? storage,
  }) : _storage = storage ?? ServicePositionStorage() {
    _state = ServiceState(
      playlistId: playlistId,
      items: initialItems,
      currentIndex: PlaylistOrderManager.clampResumePosition(
        savedPosition: initialIndex,
        totalItems: initialItems.length,
      ),
    );
    _persistPosition(_state.currentIndex);
  }

  ServiceState get state => _state;

  void next() {
    if (_state.canGoNext) {
      final newIndex = _state.currentIndex + 1;
      _state = _state.copyWith(currentIndex: newIndex);
      _persistPosition(newIndex);
      notifyListeners();
    }
  }

  void previous() {
    if (_state.canGoPrevious) {
      final newIndex = _state.currentIndex - 1;
      _state = _state.copyWith(currentIndex: newIndex);
      _persistPosition(newIndex);
      notifyListeners();
    }
  }

  void jumpTo(int index) {
    final clamped = PlaylistOrderManager.clampResumePosition(
      savedPosition: index,
      totalItems: _state.items.length,
    );
    if (clamped != _state.currentIndex) {
      _state = _state.copyWith(currentIndex: clamped);
      _persistPosition(clamped);
      notifyListeners();
    }
  }

  void toggleNotes() {
    _state = _state.copyWith(isNotesExpanded: !_state.isNotesExpanded);
    notifyListeners();
  }

  void _persistPosition(int index) {
    _storage.savePosition(_state.playlistId, index);
  }
}
