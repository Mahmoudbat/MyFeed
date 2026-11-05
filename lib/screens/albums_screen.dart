import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/gallery_service.dart';
import '../widgets/media_tile.dart';
import 'asset_grid_screen.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  final _gallery = GalleryService.instance;
  List<AssetPathEntity> _albums = [];
  bool _loading = true;
  bool _permission = true;

  @override
  void initState() {
    super.initState();
    _gallery.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _gallery.changes.removeListener(_load);
    super.dispose();
  }

  static bool _isPrimary(AssetPathEntity a) {
    final name = a.name.toLowerCase();
    return a.isAll || name.contains('recent') || name.contains('camera') || name == 'all';
  }

  Future<void> _load() async {
    if (!await _gallery.ensurePermission()) {
      if (mounted) {
        setState(() {
          _permission = false;
          _loading = false;
        });
      }
      return;
    }
    final albums = await _gallery.albums();
    albums.sort((a, b) {
      final pa = _isPrimary(a), pb = _isPrimary(b);
      if (pa != pb) return pa ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _permission = true;
      _albums = albums;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Albums')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_permission
              ? PermissionPrompt(onRetry: () async {
                  await _gallery.ensurePermission(force: true);
                  _load();
                })
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _albums.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 200),
                          Center(child: Text('No albums found', style: TextStyle(color: Colors.white70))),
                        ])
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: _albums.length,
                          itemBuilder: (context, index) {
                            final album = _albums[index];
                            return _AlbumCard(
                              key: ValueKey('${album.id}-${_gallery.changes.value}'),
                              album: album,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => AssetGridScreen(title: album.name, album: album),
                              )),
                            );
                          },
                        ),
                ),
    );
  }
}

class _AlbumCard extends StatefulWidget {
  const _AlbumCard({super.key, required this.album, required this.onTap});
  final AssetPathEntity album;
  final VoidCallback onTap;

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  int _count = 0;
  AssetEntity? _cover;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final count = await widget.album.assetCountAsync;
    // Paths are ordered newest-first, so the first item is the latest.
    final first = count == 0 ? <AssetEntity>[] : await widget.album.getAssetListRange(start: 0, end: 1);
    if (!mounted) return;
    setState(() {
      _count = count;
      _cover = first.isEmpty ? null : first.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _cover == null
                  ? const ColoredBox(color: Color(0xFF2A2A2A), child: TilePlaceholder())
                  : AssetThumbnail(asset: _cover!, size: 320),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('$_count item${_count == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white60)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
