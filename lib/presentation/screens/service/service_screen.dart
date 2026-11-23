import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:worship_setlist/data/database/database.dart';
import 'package:worship_setlist/domain/url_validator.dart';
import 'package:worship_setlist/presentation/providers/service_provider.dart';
import 'package:worship_setlist/presentation/screens/service/jump_list_sheet.dart';
import 'package:worship_setlist/presentation/screens/service/notes_panel.dart';
import 'package:worship_setlist/presentation/screens/service/service_bottom_bar.dart';

/// Full-screen live worship Service Mode screen (spec.md Section 5.3).
class ServiceScreen extends StatefulWidget {
  final int playlistId;
  final List<PlaylistItemWithSong> items;
  final int initialIndex;
  final ServiceController? controller;
  final Widget Function(BuildContext context, String url)? webViewBuilder;

  const ServiceScreen({
    super.key,
    required this.playlistId,
    required this.items,
    this.initialIndex = 0,
    this.controller,
    this.webViewBuilder,
  });

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  late final ServiceController _controller;
  WebViewController? _webViewController;
  bool _isLoading = true;
  String? _loadError;
  int _lastLoadedIndex = -1;

  @override
  void initState() {
    super.initState();
    _enableWakelock();

    _controller =
        widget.controller ??
        ServiceController(
          playlistId: widget.playlistId,
          initialItems: widget.items,
          initialIndex: widget.initialIndex,
        );

    _controller.addListener(_onControllerUpdated);

    if (widget.webViewBuilder == null) {
      _initWebViewController();
    }
  }

  void _enableWakelock() {
    try {
      WakelockPlus.enable();
    } catch (_) {
      // Gracefully ignore on unsupported test harnesses
    }
  }

  void _disableWakelock() {
    try {
      WakelockPlus.disable();
    } catch (_) {
      // Gracefully ignore on unsupported test harnesses
    }
  }

  void _initWebViewController() {
    try {
      final currentSong = _controller.state.currentItem?.song;
      final targetUrl = currentSong?.url ?? 'https://www.ultimate-guitar.com';

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              final uri = Uri.tryParse(request.url);
              if (uri != null &&
                  uri.scheme.toLowerCase() == 'https' &&
                  UrlValidator.isAllowedHost(uri.host)) {
                return NavigationDecision.navigate;
              }

              _promptOpenExternal(request.url);
              return NavigationDecision.prevent;
            },
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _loadError = null;
                });
              }
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted && error.isForMainFrame == true) {
                setState(() {
                  _isLoading = false;
                  _loadError =
                      'Failed to load chord chart (${error.description}). Please check your internet connection.';
                });
              }
            },
          ),
        );

      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        platform.setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async =>
              const GeolocationPermissionsResponse(allow: false, retain: false),
        );
      }

      _webViewController = controller;
      _webViewController!.loadRequest(Uri.parse(targetUrl));
      _lastLoadedIndex = _controller.state.currentIndex;
    } catch (_) {
      // WebViewPlatform is not registered in widget test environments
      _isLoading = false;
    }
  }

  void _onControllerUpdated() {
    if (!mounted) return;
    setState(() {});

    final currentIndex = _controller.state.currentIndex;
    if (currentIndex != _lastLoadedIndex) {
      _lastLoadedIndex = currentIndex;
      final song = _controller.state.currentItem?.song;
      if (song != null && _webViewController != null) {
        _webViewController!.loadRequest(Uri.parse(song.url));
      }
    }
  }

  Future<void> _promptOpenExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (!mounted) return;
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open External Link?'),
        content: Text(
          'This link leads outside Ultimate Guitar:\n\n$url\n\nWould you like to open it in your system browser?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open in Browser'),
          ),
        ],
      ),
    );

    if (shouldOpen == true && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<bool> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('leave_service_dialog'),
        title: const Text('Leave Service Mode?'),
        content: const Text(
          'Are you sure you want to exit Service Mode and return to the playlist?',
        ),
        actions: [
          TextButton(
            key: const Key('cancel_leave_service_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_leave_service_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    return leave ?? false;
  }

  void _showJumpList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => JumpListSheet(
        items: _controller.state.items,
        currentIndex: _controller.state.currentIndex,
        onSelectSong: (index) {
          _controller.jumpTo(index);
        },
      ),
    );
  }

  void _reloadCurrentSong() {
    final song = _controller.state.currentItem?.song;
    if (song != null && _webViewController != null) {
      _webViewController!.loadRequest(Uri.parse(song.url));
    }
  }

  @override
  void dispose() {
    _disableWakelock();
    _controller.removeListener(_onControllerUpdated);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final currentSong = state.currentItem?.song;
    final theme = Theme.of(context);
    final navigator = Navigator.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmExit();
        if (shouldLeave && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  // Full-screen WebView or custom builder
                  if (currentSong != null)
                    Positioned.fill(
                      child: widget.webViewBuilder != null
                          ? widget.webViewBuilder!(context, currentSong.url)
                          : (_webViewController != null
                                ? WebViewWidget(controller: _webViewController!)
                                : Center(
                                    key: const Key('service_webview_fallback'),
                                    child: Text(
                                      'Viewing: ${currentSong.title}',
                                    ),
                                  )),
                    )
                  else
                    const Center(child: Text('No song available in playlist')),

                  // Loading progress bar at top
                  if (_isLoading && widget.webViewBuilder == null)
                    Positioned(
                      top: MediaQuery.of(context).padding.top,
                      left: 0,
                      right: 0,
                      child: const LinearProgressIndicator(minHeight: 3),
                    ),

                  // Floating exit button
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: IconButton(
                        key: const Key('service_exit_button'),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        tooltip: 'Leave Service Mode',
                        onPressed: () async {
                          final shouldLeave = await _confirmExit();
                          if (shouldLeave && mounted) {
                            navigator.pop();
                          }
                        },
                      ),
                    ),
                  ),

                  // Load Error Overlay
                  if (_loadError != null)
                    Positioned.fill(
                      child: Container(
                        color: theme.colorScheme.surface,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 56,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load chord chart',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _reloadCurrentSong,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Collapsible Notes & Key Note Panel above bottom bar
            NotesPanel(
              currentSong: currentSong,
              isExpanded: state.isNotesExpanded,
              onToggle: _controller.toggleNotes,
            ),

            // Service Bottom Navigation Bar
            ServiceBottomBar(
              currentIndex: state.currentIndex,
              totalCount: state.items.length,
              currentSong: currentSong,
              canGoPrevious: state.canGoPrevious,
              canGoNext: state.canGoNext,
              onPrevious: _controller.previous,
              onNext: _controller.next,
              onOpenJumpList: _showJumpList,
            ),
          ],
        ),
      ),
    );
  }
}
