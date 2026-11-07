import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/gallery_service.dart';
import '../widgets/media_tile.dart';
import '../widgets/media_viewer.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/video_view.dart';
import 'gallery_actions.dart';
import 'locked/vault_actions.dart';

/// Paged, sortable, selectable grid of device-gallery media. Used for the
/// Home tab (all media) and for album details.
class AssetGridScreen extends StatefulWidget {
  const AssetGridScreen({super.key, required this.title, this.album});

  final String title;

  /// Album to show; null shows all media.
  final AssetPathEntity? album;

  @override
  State<AssetGridScreen> createState() => _AssetGridScreenState();
}

class _AssetGridScreenState extends State<AssetGridScreen> {
  static const _pageSize = 120;
  final _gallery = GalleryService.instance;

  GallerySort _sort = GallerySort.newest;
  MediaFilter _filter = MediaFilter.all;
  AssetPathEntity? _path;
  List<AssetEntity> _assets = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _permission = true;
  Object? _error;
  int _generation = 0;
  final Set<String> _selected = {};

  bool get _hasMore => _assets.length < _total;

  @override
  void initState() {
    super.initState();
    _gallery.changes.addListener(_onGalleryChanged);
    _load();
  }

  @override
  void dispose() {
    _gallery.changes.removeListener(_onGalleryChanged);
    super.dispose();
  }

  void _onGalleryChanged() => _load(keepPosition: true);

  Future<void> _load({bool keepPosition = false}) async {
    final generation = ++_generation;
    if (!keepPosition) setState(() => _loading = true);
    try {
      if (!await _gallery.ensurePermission()) {
        if (generation == _generation) {
          setState(() {
            _permission = false;
            _loading = false;
          });
        }
        return;
      }
      final ascending = _sort == GallerySort.oldest;
      final type = _filter.requestType;
      final path = widget.album == null
          ? await _gallery.allMedia(type: type, ascending: ascending)
          : await _gallery.albumView(widget.album!, type: type, ascending: ascending);
      final total = path == null ? 0 : await path.assetCountAsync;
      List<AssetEntity> assets;
      if (path == null || total == 0) {
        assets = [];
      } else if (_sort.byName) {
        // The platform can only sort by date, so name sorts load all metadata.
        assets = await path.getAssetListRange(start: 0, end: total);
        int byTitle(AssetEntity a, AssetEntity b) =>
            (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase());
        assets.sort(_sort == GallerySort.nameAsc ? byTitle : (a, b) => byTitle(b, a));
      } else {
        // When refreshing, reload at least as many items as were visible.
        final wanted = keepPosition ? max(_assets.length, _pageSize) : _pageSize;
        assets = await path.getAssetListRange(start: 0, end: min(wanted, total));
      }
      if (generation != _generation || !mounted) return;
      setState(() {
        _permission = true;
        _path = path;
        _total = total;
        _assets = assets;
        _error = null;
        _loading = false;
        final ids = assets.map((a) => a.id).toSet();
        _selected.removeWhere((id) => !ids.contains(id));
      });
    } catch (e) {
      if (generation == _generation && mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final path = _path;
    if (_loadingMore || !_hasMore || path == null) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      final more = await path.getAssetListRange(
        start: _assets.length,
        end: min(_assets.length + _pageSize, _total),
      );
      if (generation == _generation && mounted) setState(() => _assets = [..._assets, ...more]);
    } catch (e) {
      debugPrint('load more failed: $e');
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _selectAll() async {
    if (_hasMore && _path != null) {
      final all = await _path!.getAssetListRange(start: 0, end: _total);
      if (!mounted) return;
      setState(() => _selected.addAll(all.map((a) => a.id)));
    } else {
      setState(() => _selected.addAll(_assets.map((a) => a.id)));
    }
  }

  /// The selected assets, including ones not loaded yet (after "Select all").
  Future<List<AssetEntity>> _selectedAssets() async {
    final ids = Set.of(_selected);
    var assets = _assets.where((a) => ids.contains(a.id)).toList();
    if (assets.length < ids.length && _path != null) {
      final all = await _path!.getAssetListRange(start: 0, end: _total);
      assets = all.where((a) => ids.contains(a.id)).toList();
    }
    return assets;
  }

  Future<void> _shareSelected() async {
    final assets = await _selectedAssets();
    if (!mounted) return;
    await shareAssets(context, assets);
  }

  Future<void> _deleteSelected() async {
    final assets = await _selectedAssets();
    if (!mounted) return;
    final removed = await deleteAssets(context, assets);
    if (!mounted || removed.isEmpty) return;
    setState(() {
      _selected.removeAll(removed);
      _assets = _assets.where((a) => !removed.contains(a.id)).toList();
      _total -= removed.length;
    });
    _load(keepPosition: true);
  }

  Future<void> _lockSelected() async {
    final assets = await _selectedAssets();
    if (!mounted) return;
    final result = await lockAssets(context, assets);
    if (!mounted || result == null) return;
    setState(_selected.clear);
    showSnack(context, describeLockResult(result), error: result.failed > 0);
    _load(keepPosition: true);
  }

  void _open(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaViewer<AssetEntity>(
        items: _assets,
        initialIndex: index,
        pageBuilder: (context, asset, active) => AssetPage(asset: asset, active: active),
        actionsBuilder: (context, asset, viewer) => [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareAssets(context, [asset]),
          ),
          IconButton(
            tooltip: 'Move to locked gallery',
            icon: const Icon(Icons.lock_outline),
            onPressed: () async {
              final result = await lockAssets(context, [asset]);
              if (result == null || !context.mounted) return;
              showSnack(context, describeLockResult(result), error: result.failed > 0);
              if (result.removedOriginals > 0) viewer.removeCurrent();
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final removed = await deleteAssets(context, [asset]);
              if (removed.contains(asset.id)) viewer.removeCurrent();
            },
          ),
          IconButton(
            tooltip: 'Details',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAssetDetails(context, asset),
          ),
        ],
      ),
    ));
  }

  void _showSortMenu() async {
    // Returns either a MediaFilter or a GallerySort.
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) {
        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white60)),
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header('Show'),
                for (final filter in MediaFilter.values)
                  ListTile(
                    leading: Icon(filter.icon),
                    title: Text(filter.label),
                    trailing: filter == _filter ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, filter),
                  ),
                const Divider(),
                header('Sort by'),
                for (final sort in GallerySort.values)
                  ListTile(
                    title: Text(sort.label),
                    trailing: sort == _sort ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, sort),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (choice is MediaFilter && choice != _filter) {
      setState(() {
        _filter = choice;
        _selected.clear();
      });
      _load();
    } else if (choice is GallerySort && choice != _sort) {
      _sort = choice;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all), onPressed: _selectAll),
                  IconButton(tooltip: 'Share', icon: const Icon(Icons.share_outlined), onPressed: _shareSelected),
                  IconButton(
                    tooltip: 'Move to locked gallery',
                    icon: const Icon(Icons.lock_outline),
                    onPressed: _lockSelected,
                  ),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _deleteSelected),
                ],
              )
            : AppBar(
                title: _filter == MediaFilter.all
                    ? Text(widget.title)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Icon(_filter.icon, size: 20, color: Colors.white70),
                      ]),
                actions: [
                  IconButton(
                    tooltip: 'Filter and sort',
                    icon: Icon(_filter == MediaFilter.all ? Icons.sort : Icons.filter_alt),
                    onPressed: _showSortMenu,
                  ),
                ],
              ),
        body: _buildBody(),
      ),
    );
  }

  String get _emptyText => switch (_filter) {
        MediaFilter.all => 'No media found.',
        MediaFilter.photos => 'No photos found.',
        MediaFilter.videos => 'No videos found.',
      };

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_permission) {
      return PermissionPrompt(onRetry: () async {
        await _gallery.ensurePermission(force: true);
        _load();
      });
    }
    if (_error != null) {
      return Center(child: Text('Could not load media: $_error', style: const TextStyle(color: Colors.white70)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _assets.isEmpty
          ? ListView(children: [
              const SizedBox(height: 200),
              Center(child: Text(_emptyText, style: const TextStyle(color: Colors.white70))),
            ])
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 1500) _loadMore();
                return false;
              },
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: _assets.length,
                itemBuilder: (context, index) {
                  final asset = _assets[index];
                  final selected = _selected.contains(asset.id);
                  final selecting = _selected.isNotEmpty;
                  void toggle() => setState(() => selected ? _selected.remove(asset.id) : _selected.add(asset.id));
                  return MediaTile(
                    key: ValueKey(asset.id),
                    image: AssetThumbnail(asset: asset),
                    isVideo: asset.type == AssetType.video,
                    durationSeconds: asset.duration,
                    selectionMode: selecting,
                    selected: selected,
                    onTap: selecting ? toggle : () => _open(index),
                    onLongPress: toggle,
                  );
                },
              ),
            ),
    );
  }
}

/// Cached gallery thumbnail (photo_manager image provider + Flutter ImageCache).
class AssetThumbnail extends StatelessWidget {
  const AssetThumbnail({super.key, required this.asset, this.size = 256});
  final AssetEntity asset;
  final int size;

  @override
  Widget build(BuildContext context) => AssetEntityImage(
        asset,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(size),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => TilePlaceholder(isVideo: asset.type == AssetType.video),
      );
}

/// Full-screen page for a gallery asset.
class AssetPage extends StatelessWidget {
  const AssetPage({super.key, required this.asset, required this.active, this.compact = false});

  final AssetEntity asset;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (asset.type == AssetType.video) {
      return VideoView(
        active: active,
        compact: compact,
        createController: () async {
          final file = await asset.file;
          if (file == null) throw StateError('video file unavailable');
          return VideoPlayerController.file(file);
        },
      );
    }
    return ZoomableImage(image: AssetEntityImageProvider(asset, isOriginal: true));
  }
}

class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text('Gallery access required', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: const Text('Grant permission')),
            TextButton(onPressed: PhotoManager.openSetting, child: const Text('Open settings')),
          ],
        ),
      );
}
