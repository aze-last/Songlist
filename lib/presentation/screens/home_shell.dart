import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/services/update_service.dart';
import '../providers/database_provider.dart';
import '../widgets/update_flow.dart';
import 'playlists/playlists_screen.dart';
import 'settings/settings_screen.dart';
import 'songs/songs_screen.dart';

/// Main navigation shell with bottom navigation between Playlists, Song Library, and Settings.
/// Coordinates background 24h update auto-checks and APK cache cleanup on app launch.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    PlaylistsScreen(),
    SongsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupUpdateCheck();
    });
  }

  Future<void> _runStartupUpdateCheck() async {
    final updateService = ref.read(updateServiceProvider);
    final db = ref.read(databaseProvider);

    // 1. Cleanup any stale downloaded APKs from previous sessions
    await updateService.deleteCachedApks();

    // 2. Suspended while Service Mode is active (Route check)
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    try {
      final settings = await db.getOrCreateSettings();
      final result = await updateService.checkForUpdate(
        manual: false,
        skippedVersion: settings.skippedVersion,
        lastCheckAt: settings.lastUpdateCheck,
      );

      if (result.status == UpdateCheckStatus.updateAvailable &&
          result.releaseInfo != null) {
        // Double-check if still top route (user did not navigate into Service Mode)
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
          return;
        }

        var currentVersion = '1.0.0';
        try {
          final info = await PackageInfo.fromPlatform();
          currentVersion = info.version;
        } catch (_) {}

        await db.updateSettings(lastUpdateCheck: DateTime.now());

        if (mounted) {
          await showUpdateFlow(
            context: context,
            ref: ref,
            releaseInfo: result.releaseInfo!,
            currentVersion: currentVersion,
          );
        }
      } else if (result.status == UpdateCheckStatus.upToDate) {
        await db.updateSettings(lastUpdateCheck: DateTime.now());
      }
    } catch (_) {
      // Background auto-check fails silently without annoying the user on startup
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            key: Key('nav_playlists_tab'),
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music_rounded),
            label: 'Playlists',
          ),
          NavigationDestination(
            key: Key('nav_songs_tab'),
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Song Library',
          ),
          NavigationDestination(
            key: Key('nav_settings_tab'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
