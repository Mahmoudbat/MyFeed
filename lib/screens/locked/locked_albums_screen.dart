import 'package:flutter/material.dart';

import '../../vault/models.dart';
import '../../vault/vault_session.dart';
import '../../widgets/progress_dialog.dart';
import 'locked_settings_screen.dart';
import 'locked_widgets.dart';
import 'vault_actions.dart';

VaultSession get _session => VaultSession.instance;

class LockedAlbumsTab extends StatelessWidget {
  const LockedAlbumsTab({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await promptText(context, title: 'New album', hint: 'Album name', action: 'Create');
    if (name != null) await _session.store.createAlbum(name);
  }

  Future<void> _manage(BuildContext context, LockedAlbum album) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete album'),
              subtitle: const Text('The photos and videos stay in the locked gallery'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      final name = await promptText(context, title: 'Rename album', initial: album.name, action: 'Save');
      if (name != null) await _session.store.renameAlbum(album.id, name);
    } else if (action == 'delete') {
      if (await confirm(context,
          title: 'Delete "${album.name}"?',
          message: 'Only the album is removed; its items stay in the locked gallery.',
          action: 'Delete',
          destructive: true)) {
        await _session.store.deleteAlbum(album.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session.store,
      builder: (context, _) {
        final albums = _session.store.albums;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Locked Albums'),
            actions: [
              IconButton(tooltip: 'New album', icon: const Icon(Icons.add), onPressed: () => _create(context)),
              ...lockedCommonActions(context, settings: () => const LockedSettingsScreen()),
            ],
          ),
          body: albums.isEmpty
              ? const Center(
                  child: Text('No locked albums.\nTap + to create one.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final items = _session.store.itemsOf(album);
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        settings: const RouteSettings(name: '/vault/album'),
                        builder: (_) => LockedAlbumDetailScreen(albumId: album.id),
                      )),
                      onLongPress: () => _manage(context, album),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        margin: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: items.isEmpty
                                  ? const ColoredBox(
                                      color: Color(0xFF2A2A2A),
                                      child: Icon(Icons.photo_album, size: 48, color: Colors.white38),
                                    )
                                  : LockedThumbnail(item: items.first),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(album.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  Text('${items.length} item${items.length == 1 ? '' : 's'}',
                                      style: const TextStyle(color: Colors.white60)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class LockedAlbumDetailScreen extends StatefulWidget {
  const LockedAlbumDetailScreen({super.key, required this.albumId});
  final String albumId;

  @override
  State<LockedAlbumDetailScreen> createState() => _LockedAlbumDetailScreenState();
}

class _LockedAlbumDetailScreenState extends State<LockedAlbumDetailScreen> {
  final Set<String> _selected = {};

  Future<void> _addItems(LockedAlbum album) async {
    final picked = await Navigator.of(context).push<Set<String>>(MaterialPageRoute(
      settings: const RouteSettings(name: '/vault/pick'),
      builder: (_) => _LockedItemPicker(exclude: album.itemIds.toSet()),
    ));
    if (picked != null && picked.isNotEmpty) await _session.store.addToAlbum(album.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session.store,
      builder: (context, _) {
        final album = _session.store.albumById(widget.albumId);
        if (album == null) return const Scaffold();
        final items = _session.store.itemsOf(album);
        _selected.removeWhere((id) => !album.itemIds.contains(id));
        final selecting = _selected.isNotEmpty;
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            appBar: selecting
                ? AppBar(
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
                    title: Text('${_selected.length} selected'),
                    actions: [
                      IconButton(
                        tooltip: 'Restore to gallery',
                        icon: const Icon(Icons.lock_open),
                        onPressed: () async {
                          await restoreToGallery(
                              context, items.where((i) => _selected.contains(i.id)).toList());
                          if (mounted) setState(_selected.clear);
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove from album',
                        icon: const Icon(Icons.playlist_remove),
                        onPressed: () async {
                          await _session.store.removeFromAlbum(album.id, _selected);
                          if (mounted) setState(_selected.clear);
                        },
                      ),
                    ],
                  )
                : AppBar(
                    title: Text(album.name),
                    actions: [
                      IconButton(
                        tooltip: 'Add items',
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        onPressed: () => _addItems(album),
                      ),
                    ],
                  ),
            body: LockedItemGrid(
              items: items,
              selected: _selected,
              onChanged: () => setState(() {}),
              onOpen: (index) => openLockedViewer(context, items, index),
              emptyText: 'This album is empty.\nTap + to add locked items.',
            ),
          ),
        );
      },
    );
  }
}

class _LockedItemPicker extends StatefulWidget {
  const _LockedItemPicker({required this.exclude});
  final Set<String> exclude;

  @override
  State<_LockedItemPicker> createState() => _LockedItemPickerState();
}

class _LockedItemPickerState extends State<_LockedItemPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final items = _session.store.items.where((i) => !widget.exclude.contains(i.id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? 'Select items' : '${_selected.length} selected'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
            child: const Text('Add'),
          ),
        ],
      ),
      body: LockedItemGrid(
        items: items,
        selected: _selected,
        selectionOnly: true,
        onChanged: () => setState(() {}),
        onOpen: (_) {},
        emptyText: 'Every locked item is already in this album.',
      ),
    );
  }
}
