import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/gallery_service.dart';
import '../services/settings_service.dart';
import 'album_detail_screen.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  final GalleryService _galleryService = GalleryService();
  final SettingsService _settingsService = SettingsService();
  List<AssetPathEntity> _albums = [];
  bool _isLoading = true;
  bool _permissionGranted = false;
  bool _scrollVertical = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() => _isLoading = true);
    
    final hasPermission = await _galleryService.requestPermissions();
    if (!hasPermission) {
      setState(() {
        _isLoading = false;
        _permissionGranted = false;
      });
      return;
    }
    
    setState(() => _permissionGranted = true);
    
    final albums = await _galleryService.getAllAlbums();
    final scrollVertical = await _settingsService.getScrollDirectionVertical();
    
    // Sort albums: Camera/Recent first, then alphabetically
    albums.sort((a, b) {
      // Priority for common "all" album names
      final aIsAll = a.name.toLowerCase().contains('recent') || 
                     a.name.toLowerCase().contains('camera') ||
                     a.name.toLowerCase() == 'all';
      final bIsAll = b.name.toLowerCase().contains('recent') || 
                     b.name.toLowerCase().contains('camera') ||
                     b.name.toLowerCase() == 'all';
      
      if (aIsAll && !bIsAll) return -1;
      if (!aIsAll && bIsAll) return 1;
      
      return a.name.compareTo(b.name);
    });
    
    setState(() {
      _albums = albums;
      _scrollVertical = scrollVertical;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.photo_album, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        'Gallery access required',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _loadAlbums,
                        child: const Text('Grant Permission'),
                      ),
                    ],
                  ),
                )
              : _albums.isEmpty
                  ? Center(
                      child: Text(
                        'No albums found',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      scrollDirection: _scrollVertical ? Axis.vertical : Axis.horizontal,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: _scrollVertical ? 0.8 : 1.25,
                      ),
                      itemCount: _albums.length,
                      itemBuilder: (context, index) {
                        final album = _albums[index];
                        return _AlbumCard(
                          album: album,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AlbumDetailScreen(album: album),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}

class _AlbumCard extends StatefulWidget {
  final AssetPathEntity album;
  final VoidCallback onTap;

  const _AlbumCard({
    required this.album,
    required this.onTap,
  });

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  int _itemCount = 0;
  AssetEntity? _coverAsset;

  @override
  void initState() {
    super.initState();
    _loadAlbumInfo();
  }

  Future<void> _loadAlbumInfo() async {
    final count = await widget.album.assetCountAsync;
    // Get the last item as album cover (most recent)
    final assets = await widget.album.getAssetListRange(start: count > 0 ? count - 1 : 0, end: count);
    
    if (mounted) {
      setState(() {
        _itemCount = count;
        _coverAsset = assets.isNotEmpty ? assets.first : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: _coverAsset == null
                    ? Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(Icons.photo_album, size: 48, color: Colors.white38),
                        ),
                      )
                    : FutureBuilder<Uint8List?>(
                        future: _coverAsset!.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            );
                          }
                          return Container(
                            color: Colors.grey[800],
                            child: const Center(child: CircularProgressIndicator()),
                          );
                        },
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.album.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_itemCount items',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
