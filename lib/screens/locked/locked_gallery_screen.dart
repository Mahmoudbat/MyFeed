import 'package:flutter/material.dart';

import '../../vault/models.dart';
import '../../vault/vault_session.dart';
import '../../widgets/progress_dialog.dart';
import 'locked_albums_screen.dart';
import 'locked_settings_screen.dart';
import 'locked_widgets.dart';
import 'vault_actions.dart';

VaultSession get _session => VaultSession.instance;

/// Shell of the unlocked vault. Leaving it locks the vault; locking (manual,
/// or automatic when the app is backgrounded) removes it and every vault
/// route above it.
class LockedGalleryScreen extends StatefulWidget {
  const LockedGalleryScreen({super.key});

  @override
  State<LockedGalleryScreen> createState() => _LockedGalleryScreenState();
}

class _LockedGalleryScreenState extends State<LockedGalleryScreen> {
  int _tab = 0;
  final Set<int> _visited = {0};

  @override
  void dispose() {
    // Defer: locking notifies listeners, which must not happen mid-teardown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _session.lock());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const LockedHomeTab(),
      LockedReelsTab(active: _tab == 1),
      const LockedAlbumsTab(),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [for (var i = 0; i < pages.length; i++) _visited.contains(i) ? pages[i] : const SizedBox()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Locked'),
          NavigationDestination(icon: Icon(Icons.video_library), label: 'Reels'),
          NavigationDestination(icon: Icon(Icons.photo_album), label: 'Albums'),
        ],
      ),
    );
  }
}

class LockedHomeTab extends StatefulWidget {
  const LockedHomeTab({super.key});

  @override
  State<LockedHomeTab> createState() => _LockedHomeTabState();
}

class _LockedHomeTabState extends State<LockedHomeTab> {
  final Set<String> _selected = {};

  List<LockedItem> _selectedItems() =>
      _session.store.items.where((i) => _selected.contains(i.id)).toList();

  Future<void> _delete() async {
    final count = _selected.length;
    if (!await confirm(context,
        title: 'Delete $count item${count == 1 ? '' : 's'}?',
        message: 'They will be permanently erased from the locked gallery. This cannot be undone.',
        action: 'Delete',
        destructive: true)) {
      return;
    }
    await _session.store.deleteItems(_selected.toList());
    if (!mounted) return;
    setState(_selected.clear);
    showSnack(context, 'Deleted $count item${count == 1 ? '' : 's'}');
  }

  Future<void> _addToAlbum() async {
    final albumId = await pickAlbum(context);
    if (albumId == null) return;
    await _session.store.addToAlbum(albumId, _selected);
    if (!mounted) return;
    showSnack(context, 'Added ${_selected.length} to ${_session.store.albumById(albumId)?.name}');
    setState(_selected.clear);
  }

  Future<void> _restore() async {
    await restoreToGallery(context, _selectedItems());
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session.store,
      builder: (context, _) {
        final items = _session.store.items;
        _selected.removeWhere((id) => _session.store.itemById(id) == null);
        final selecting = _selected.isNotEmpty;
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            appBar: selecting
                ? AppBar(
                    leading: IconButton(
                      tooltip: 'Cancel selection',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_selected.clear),
                    ),
                    title: Text('${_selected.length} selected'),
                    actions: [
                      IconButton(
                        tooltip: 'Select all',
                        icon: const Icon(Icons.select_all),
                        onPressed: () => setState(() => _selected.addAll(items.map((i) => i.id))),
                      ),
                      IconButton(tooltip: 'Add to album', icon: const Icon(Icons.playlist_add), onPressed: _addToAlbum),
                      IconButton(tooltip: 'Restore to gallery', icon: const Icon(Icons.lock_open), onPressed: _restore),
                      IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
                    ],
                  )
                : AppBar(
                    title: const Text('Locked Gallery'),
                    actions: lockedCommonActions(context, settings: () => const LockedSettingsScreen()),
                  ),
            body: LockedItemGrid(
              items: items,
              selected: _selected,
              onChanged: () => setState(() {}),
              onOpen: (index) => openLockedViewer(context, items, index),
              emptyText: 'No locked media yet.\n\nLong-press photos or videos in the gallery and tap the lock icon to move them here.',
            ),
          ),
        );
      },
    );
  }
}

class LockedReelsTab extends StatefulWidget {
  const LockedReelsTab({super.key, required this.active});
  final bool active;

  @override
  State<LockedReelsTab> createState() => _LockedReelsTabState();
}

class _LockedReelsTabState extends State<LockedReelsTab> {
  final PageController _controller = PageController();
  List<LockedItem> _videos = [];
  int _current = 0;
  int _knownCount = -1;

  @override
  void initState() {
    super.initState();
    _session.store.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _session.store.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the shuffled order stable; only drops deleted videos / adds new ones.
  void _sync({bool reshuffle = false}) {
    if (!_session.store.isUnlocked) return;
    final videos = _session.store.items.where((i) => i.isVideo).toList();
    if (reshuffle || _knownCount < 0) {
      videos.shuffle();
      _videos = videos;
      _current = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    } else {
      final ids = videos.map((v) => v.id).toSet();
      final kept = _videos.where((v) => ids.contains(v.id)).toList();
      final keptIds = kept.map((v) => v.id).toSet();
      _videos = [...kept, ...videos.where((v) => !keptIds.contains(v.id))];
      if (_current >= _videos.length) _current = _videos.isEmpty ? 0 : _videos.length - 1;
    }
    _knownCount = videos.length;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Locked Reels'),
        actions: [
          IconButton(tooltip: 'Shuffle', icon: const Icon(Icons.shuffle), onPressed: () => _sync(reshuffle: true)),
          ...lockedCommonActions(context, settings: () => const LockedSettingsScreen()),
        ],
      ),
      body: _videos.isEmpty
          ? const Center(child: Text('No locked videos yet.', style: TextStyle(color: Colors.white70)))
          : PageView.builder(
              controller: _controller,
              scrollDirection: Axis.vertical,
              itemCount: _videos.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, index) {
                final item = _videos[index];
                return Stack(
                  key: ValueKey(item.id),
                  fit: StackFit.expand,
                  children: [
                    LockedMediaPage(item: item, compact: true, active: widget.active && index == _current),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: IgnorePointer(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [
                            Shadow(blurRadius: 6, color: Colors.black),
                          ]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
