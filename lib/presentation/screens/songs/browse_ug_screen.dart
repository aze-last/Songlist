import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:worship_setlist/domain/url_validator.dart';
import 'package:worship_setlist/presentation/providers/songs_provider.dart';

/// In-app WebView screen to browse Ultimate Guitar and save songs (spec.md Sections 3 & 5.1).
class BrowseUgScreen extends ConsumerStatefulWidget {
  final String initialUrl;

  const BrowseUgScreen({
    super.key,
    this.initialUrl = 'https://www.ultimate-guitar.com',
  });

  @override
  ConsumerState<BrowseUgScreen> createState() => _BrowseUgScreenState();
}

class _BrowseUgScreenState extends ConsumerState<BrowseUgScreen> {
  late final WebViewController _controller;
  String? _currentUrl;
  String? _currentPageTitle;
  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _initWebViewController();
  }

  void _initWebViewController() {
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

            // Block third-party URLs and offer to open in system browser
            _promptOpenInExternalBrowser(request.url);
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _isLoading = true;
                _loadError = null;
              });
            }
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            final title = await _controller.getTitle();
            setState(() {
              _currentUrl = url;
              _currentPageTitle = title;
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _isLoading = false;
                _loadError =
                    'Failed to load page (${error.description}). Please check your internet connection.';
              });
            }
          },
        ),
      );

    // Disable file access and content access on Android
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // Disallow file scheme access from WebView
      platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async =>
            const GeolocationPermissionsResponse(allow: false, retain: false),
      );
    }

    _controller = controller;
    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _promptOpenInExternalBrowser(String blockedUrl) async {
    final uri = Uri.tryParse(blockedUrl);
    if (uri == null) return;

    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('External Link Blocked'),
        content: Text(
          'Navigation inside the app is restricted to Ultimate Guitar.\n\nWould you like to open this link in your device\'s system browser?\n\n$blockedUrl',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open in Browser'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  bool get _isSongTabPage {
    if (_currentUrl == null) return false;
    final validation = UrlValidator.validateAndNormalize(_currentUrl!);
    return validation.isValid;
  }

  Future<void> _handleSaveThisSong() async {
    if (!_isSongTabPage || _currentUrl == null) return;

    final validation = UrlValidator.validateAndNormalize(_currentUrl!);
    if (!validation.isValid) return;

    final normalizedUrl = validation.normalizedUrl!;

    // Derive a sensible initial title from page title or URL
    var initialTitle = _currentPageTitle?.trim() ?? '';
    // Clean up Ultimate Guitar page title suffix (e.g. "Song Name Chords by Artist @ Ultimate-Guitar.Com")
    if (initialTitle.toLowerCase().contains('ultimate-guitar')) {
      final parts = initialTitle.split(RegExp(r'\||@'));
      if (parts.isNotEmpty) {
        initialTitle = parts.first.trim();
      }
    }
    if (initialTitle.isEmpty) {
      final segments = Uri.parse(normalizedUrl).pathSegments;
      if (segments.length >= 2) {
        initialTitle = segments.last.replaceAll('-', ' ');
      }
    }

    final titleController = TextEditingController(text: initialTitle);
    final keyNoteController = TextEditingController();
    final notesController = TextEditingController();

    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Save Song to Library',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              normalizedUrl,
              style: Theme.of(ctx).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Song Title *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyNoteController,
              decoration: const InputDecoration(
                labelText: 'Key note (optional)',
                hintText: 'e.g. Play in G, Capo 2',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Intro 4 bars, repeat chorus',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check),
              label: const Text('Save to Library'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      final error = await ref
          .read(songsControllerProvider.notifier)
          .addSong(
            rawUrl: normalizedUrl,
            title: titleController.text,
            keyNote: keyNoteController.text,
            notes: notesController.text,
          );

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "${titleController.text.trim()}" to library!'),
          ),
        );
        Navigator.pop(context); // Return to library
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSong = _isSongTabPage;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentPageTitle ?? 'Browse Ultimate Guitar',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () {
              setState(() => _loadError = null);
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connection Error',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() => _loadError = null);
                        _controller.reload();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () async {
                  if (await _controller.canGoBack()) {
                    await _controller.goBack();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'Forward',
                onPressed: () async {
                  if (await _controller.canGoForward()) {
                    await _controller.goForward();
                  }
                },
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: (isSong && !_isSaving) ? _handleSaveThisSong : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add_rounded),
                label: Text(isSong ? 'Save this song' : 'Navigate to a tab'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
