import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../util/format.dart';
import '../../vault/locked_image.dart';
import '../../vault/models.dart';
import '../../vault/vault_session.dart';
import '../../widgets/media_tile.dart';
import '../../widgets/media_viewer.dart';
import '../../widgets/progress_dialog.dart';
import '../../widgets/video_view.dart';
import 'vault_actions.dart';

VaultSession get _session => VaultSession.instance;

/// Grid thumbnail for a vault item (decrypted through the image cache).
class LockedThumbnail extends StatelessWidget {
  const LockedThumbnail({super.key, required this.item});
  final LockedItem item;

  @override
  Widget build(BuildContext context) {
    if (!item.hasThumbnail) return TilePlaceholder(isVideo: item.isVideo);
    return Image(
      image: ResizeImage(LockedImage(_session.store, item.id, thumbnail: true), width: 320, height: 320,
          policy: ResizeImagePolicy.fit),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => TilePlaceholder(isVideo: item.isVideo),
    );
  }
}

/// Selectable grid of vault items.
class LockedItemGrid extends StatelessWidget {
  const LockedItemGrid({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.onOpen,
    this.selectionOnly = false,
    this.emptyText = 'Nothing here yet',
  });

  final List<LockedItem> items;
  final Set<String> selected;
  final VoidCallback onChanged;
  final void Function(int index) onOpen;
  final bool selectionOnly;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final selectionMode = selectionOnly || selected.isNotEmpty;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = selected.contains(item.id);
        void toggle() {
          isSelected ? selected.remove(item.id) : selected.add(item.id);
          onChanged();
        }

        return MediaTile(
          key: ValueKey(item.id),
          image: LockedThumbnail(item: item),
          isVideo: item.isVideo,
          durationSeconds: item.durationSeconds,
          selectionMode: selectionMode,
          selected: isSelected,
          onTap: selectionMode ? toggle : () => onOpen(index),
          onLongPress: selectionOnly ? null : toggle,
        );
      },
    );
  }
}

/// Opens the full-screen viewer for vault items.
void openLockedViewer(BuildContext context, List<LockedItem> items, int index) {
  Navigator.of(context).push(MaterialPageRoute(
    settings: const RouteSettings(name: '/vault/viewer'),
    builder: (_) => MediaViewer<LockedItem>(
      items: items,
      initialIndex: index,
      pageBuilder: (context, item, active) => LockedMediaPage(item: item, active: active),
      actionsBuilder: (context, item, viewer) => [
        IconButton(
          tooltip: 'Details',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showLockedItemInfo(context, item),
        ),
        IconButton(
          tooltip: 'Restore to gallery',
          icon: const Icon(Icons.lock_open),
          onPressed: () async {
            await restoreToGallery(context, [item]);
            if (_session.store.itemById(item.id) == null) viewer.removeCurrent();
          },
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (!await confirm(context,
                title: 'Delete permanently?',
                message: 'This item will be erased from the locked gallery. This cannot be undone.',
                action: 'Delete',
                destructive: true)) {
              return;
            }
            await _session.store.deleteItems([item.id]);
            viewer.removeCurrent();
          },
        ),
      ],
    ),
  ));
}

class LockedMediaPage extends StatelessWidget {
  const LockedMediaPage({super.key, required this.item, required this.active, this.compact = false});

  final LockedItem item;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!item.isVideo) {
      return ZoomableImage(image: LockedImage(_session.store, item.id));
    }
    return VideoView(
      compact: compact,
      active: active,
      createController: () async {
        final server = _session.mediaServer;
        await server.start();
        return VideoPlayerController.networkUrl(server.urlFor(item.id));
      },
    );
  }
}

void showLockedItemInfo(BuildContext context, LockedItem item) {
  String date(DateTime? d) => d == null ? '—' : d.toLocal().toString().split('.').first;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type: ${item.isVideo ? 'Video' : 'Photo'} (${item.extension})'),
          Text('Size: ${formatBytes(item.size)}'),
          if (item.width > 0) Text('Dimensions: ${item.width} × ${item.height}'),
          if (item.isVideo && item.durationSeconds > 0) Text('Duration: ${formatSeconds(item.durationSeconds)}'),
          Text('Created: ${date(item.createdAt)}'),
          Text('Locked: ${date(item.addedAt)}'),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ),
  );
}

/// Lets the user pick an existing album or create one. Returns the album id.
Future<String?> pickAlbum(BuildContext context) async {
  final store = _session.store;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add to album'),
      children: [
        for (final album in store.albums)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, album.id),
            child: Text(album.name),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, ''),
          child: const Row(children: [Icon(Icons.add, size: 20), SizedBox(width: 8), Text('New album…')]),
        ),
      ],
    ),
  );
  if (choice == null) return null;
  if (choice.isNotEmpty) return choice;
  if (!context.mounted) return null;
  final name = await promptText(context, title: 'New album', hint: 'Album name', action: 'Create');
  if (name == null) return null;
  return (await store.createAlbum(name)).id;
}

/// App-bar actions shown in every locked tab.
List<Widget> lockedCommonActions(BuildContext context, {required Widget Function() settings}) => [
      IconButton(
        tooltip: 'Lock now',
        icon: const Icon(Icons.lock),
        onPressed: () => _session.lock(),
      ),
      IconButton(
        tooltip: 'Locked gallery settings',
        icon: const Icon(Icons.settings),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: '/vault/settings'),
          builder: (_) => settings(),
        )),
      ),
    ];
